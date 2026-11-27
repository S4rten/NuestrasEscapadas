import Foundation
import SwiftUI
import UIKit
import UserNotifications

// ============================================================================
// AVISOS EN EL iPHONE (notificaciones locales)
// Las programa cada iPhone por su cuenta a partir de los datos sincronizados,
// así que no necesitan servidor ni la cuenta de desarrollador de pago.
// Cada vez que cambia algo (un vuelo, un plan, la maleta…) se reprograman todas.
// ============================================================================

enum ClaveAviso {
    static let activados = "avisos_activados"
    static let cuentaAtras = "avisos_cuenta_atras"
    static let reservas = "avisos_reservas"
    static let planes = "avisos_planes"
    static let fechas = "avisos_fechas"
    static let maleta = "avisos_maleta"
}

@MainActor
final class Avisos: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let compartido = Avisos()

    @Published private(set) var permiso: UNAuthorizationStatus = .notDetermined

    private let centro = UNUserNotificationCenter.current()
    private let prefijo = "escapadas."
    /// iOS permite como mucho 64 avisos pendientes por app.
    private let maximo = 60

    private override init() {
        super.init()
    }

    /// Se llama al arrancar: muestra los avisos también con la app abierta.
    func configurar() {
        centro.delegate = self
        Task { await actualizarPermiso() }
    }

    func actualizarPermiso() async {
        let ajustes = await centro.notificationSettings()
        permiso = ajustes.authorizationStatus
    }

    /// Pide permiso la primera vez. Devuelve true si se pueden mandar avisos.
    @discardableResult
    func pedirPermiso() async -> Bool {
        await actualizarPermiso()
        if permiso == .notDetermined {
            _ = try? await centro.requestAuthorization(options: [.alert, .sound, .badge])
            await actualizarPermiso()
        }
        return permiso == .authorized || permiso == .provisional || permiso == .ephemeral
    }

    private func activo(_ clave: String) -> Bool {
        let d = UserDefaults.standard
        if d.object(forKey: clave) == nil { return true }
        return d.bool(forKey: clave)
    }

    // MARK: Programación

    private struct Aviso {
        let id: String
        let fecha: Date
        let titulo: String
        let cuerpo: String
    }

    /// Borra los avisos de la app y vuelve a programarlos con los datos actuales.
    func reprogramar(almacen: Almacen, miId: String) async {
        let pendientes = await centro.pendingNotificationRequests()
        let nuestros = pendientes.map { $0.identifier }.filter { $0.hasPrefix(prefijo) }
        centro.removePendingNotificationRequests(withIdentifiers: nuestros)

        guard activo(ClaveAviso.activados) else { return }
        guard await pedirPermiso() else { return }

        let ahora = Date()
        let lista = construirAvisos(almacen: almacen, miId: miId)
            .filter { $0.fecha > ahora }
            .sorted { $0.fecha < $1.fecha }
            .prefix(maximo)

        for aviso in lista {
            let contenido = UNMutableNotificationContent()
            contenido.title = aviso.titulo
            contenido.body = aviso.cuerpo
            contenido.sound = .default
            let partes = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: aviso.fecha)
            let disparador = UNCalendarNotificationTrigger(dateMatching: partes, repeats: false)
            let peticion = UNNotificationRequest(identifier: prefijo + aviso.id, content: contenido, trigger: disparador)
            try? await centro.add(peticion)
        }
    }

    private func construirAvisos(almacen: Almacen, miId: String) -> [Aviso] {
        var avisos: [Aviso] = []
        let cal = Calendar.current
        func a(_ dia: Date, hora: Int, minuto: Int = 0) -> Date {
            cal.date(bySettingHour: hora, minute: minuto, second: 0, of: dia) ?? dia
        }

        let futuras = almacen.escapadas.filter { !$0.yaVivida }

        for e in futuras {
            let oculta = e.sorpresaOculta(para: miId)
            let nombre = oculta ? "vuestro plan sorpresa 🎁" : "\(e.icono) \(e.titulo)"
            let inicio = e.fechaInicio.inicioDelDia

            // Cuenta atrás
            if activo(ClaveAviso.cuentaAtras) {
                avisos.append(Aviso(
                    id: "cuenta7-\(e.id)",
                    fecha: a(inicio.sumando(dias: -7), hora: 10),
                    titulo: "¡Falta una semana!",
                    cuerpo: "En 7 días empieza \(nombre)."
                ))
                avisos.append(Aviso(
                    id: "cuenta1-\(e.id)",
                    fecha: a(inicio.sumando(dias: -1), hora: 10),
                    titulo: "¡Mañana os vais! ✈️",
                    cuerpo: "Mañana empieza \(nombre). ¿Lo tenéis todo?"
                ))
            }

            // Maleta: 2 días antes, si queda algo por marcar (lo mío o lo de los dos)
            if activo(ClaveAviso.maleta) {
                let pendientes = almacen.checklistDe(e.id).filter {
                    !$0.completado && ($0.asignadoAId.isEmpty || $0.asignadoAId == miId)
                }
                if !pendientes.isEmpty {
                    avisos.append(Aviso(
                        id: "maleta-\(e.id)",
                        fecha: a(inicio.sumando(dias: -2), hora: 20),
                        titulo: "🧳 Maleta",
                        cuerpo: "Tenéis \(pendientes.count) \(pendientes.count == 1 ? "cosa" : "cosas") sin marcar en la lista de \(nombre)."
                    ))
                }
            }

            // Lo que sigue destapa el destino: nunca para una sorpresa oculta.
            if oculta { continue }

            if activo(ClaveAviso.reservas) {
                for v in almacen.vuelosDe(e.id) {
                    let detalle = [v.aerolinea, v.numeroVuelo, v.terminalPuerta].filter { !$0.isEmpty }.joined(separator: " · ")
                    avisos.append(Aviso(
                        id: "vuelo-\(v.id)",
                        fecha: v.fechaHoraSalida.addingTimeInterval(-3 * 3600),
                        titulo: "✈️ Vuelo \(v.origen) → \(v.destino) en 3 h",
                        cuerpo: "Sale a las \(v.horaSalidaLocal) (hora local).\(detalle.isEmpty ? "" : " \(detalle)")"
                    ))
                }
                for t in almacen.trenesDe(e.id) {
                    avisos.append(Aviso(
                        id: "tren-\(t.id)",
                        fecha: t.fechaHoraSalida.addingTimeInterval(-2 * 3600),
                        titulo: "🚂 Tren a \(t.estacionDestino) en 2 h",
                        cuerpo: "Sale de \(t.estacionOrigen) a las \(t.fechaHoraSalida.formatted(date: .omitted, time: .shortened)) (\(t.operadora))."
                    ))
                }
                for h in almacen.alojamientosDe(e.id) {
                    let nombreAloj = h.nombre.isEmpty ? "el alojamiento" : h.nombre
                    avisos.append(Aviso(
                        id: "checkin-\(h.id)",
                        fecha: h.entrada.addingTimeInterval(-3600),
                        titulo: "🔑 Check-in en 1 h",
                        cuerpo: "Entrada en \(nombreAloj) a las \(h.entrada.formatted(date: .omitted, time: .shortened))."
                    ))
                    avisos.append(Aviso(
                        id: "checkout-\(h.id)",
                        fecha: h.salida.addingTimeInterval(-2 * 3600),
                        titulo: "🧳 Check-out en 2 h",
                        cuerpo: "Hay que dejar \(nombreAloj) a las \(h.salida.formatted(date: .omitted, time: .shortened))."
                    ))
                }
            }

            if activo(ClaveAviso.planes) {
                for act in almacen.actividadesDe(e.id) where !act.completada {
                    if act.todoElDia {
                        avisos.append(Aviso(
                            id: "plan-\(act.id)",
                            fecha: a(e.fechaParaDia(act.dia), hora: 8, minuto: 30),
                            titulo: "🌞 Hoy toca: \(act.nombreSitio)",
                            cuerpo: "Plan para todo el día. ¡A disfrutar!"
                        ))
                    } else if let hora = act.hora {
                        avisos.append(Aviso(
                            id: "plan-\(act.id)",
                            fecha: hora.addingTimeInterval(-30 * 60),
                            titulo: "📍 En 30 min: \(act.nombreSitio)",
                            cuerpo: "A las \(hora.formatted(date: .omitted, time: .shortened))."
                        ))
                    }
                }
            }
        }

        // Fechas especiales
        if activo(ClaveAviso.fechas) {
            for f in almacen.fechasEspeciales {
                guard let proxima = f.proximaOcurrencia() else { continue }
                let nombre = "\(f.emoji) \(f.titulo)"
                avisos.append(Aviso(
                    id: "fecha21-\(f.id)",
                    fecha: a(proxima.sumando(dias: -21), hora: 10),
                    titulo: "Faltan 3 semanas: \(nombre)",
                    cuerpo: "¿Y si planeáis una escapada para celebrarlo?"
                ))
                avisos.append(Aviso(
                    id: "fecha1-\(f.id)",
                    fecha: a(proxima.sumando(dias: -1), hora: 10),
                    titulo: "Mañana: \(nombre)",
                    cuerpo: "No se te olvide 😉"
                ))
                let anos = f.anosQueSeCumplen()
                avisos.append(Aviso(
                    id: "fecha0-\(f.id)",
                    fecha: a(proxima, hora: 9),
                    titulo: "¡Hoy es el día! \(nombre)",
                    cuerpo: anos.map { "Se cumplen \($0) \($0 == 1 ? "año" : "años"). ❤️" } ?? "❤️"
                ))
            }
        }

        return avisos
    }

    // MARK: Delegado (avisos también con la app abierta)

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

extension Almacen {
    /// Resumen de todo lo que afecta a los avisos: si cambia, se reprograman.
    var firmaAvisos: String {
        var partes: [String] = []
        for e in escapadas {
            partes.append("e\(e.id)\(e.fechaInicio.timeIntervalSince1970)\(e.titulo)\(e.esSorpresa)\(e.diasRevelarAntes)")
        }
        for v in vuelos { partes.append("v\(v.id)\(v.fechaHoraSalida.timeIntervalSince1970)\(v.terminalPuerta)") }
        for t in trenes { partes.append("t\(t.id)\(t.fechaHoraSalida.timeIntervalSince1970)") }
        for h in alojamientos { partes.append("h\(h.id)\(h.entrada.timeIntervalSince1970)\(h.salida.timeIntervalSince1970)") }
        for a in actividades {
            partes.append("a\(a.id)\(a.hora?.timeIntervalSince1970 ?? 0)\(a.todoElDia)\(a.completada)\(a.dia)")
        }
        for f in fechasEspeciales { partes.append("f\(f.id)\(f.fecha.timeIntervalSince1970)\(f.titulo)") }
        partes.append("c\(checklist.filter { !$0.completado }.count)")
        return partes.joined(separator: "|")
    }
}

/// Ajustes de los avisos (sección dentro de Ajustes).
struct SeccionAjustesAvisos: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @ObservedObject private var avisos = Avisos.compartido

    @AppStorage(ClaveAviso.activados) private var activados = true
    @AppStorage(ClaveAviso.cuentaAtras) private var cuentaAtras = true
    @AppStorage(ClaveAviso.reservas) private var reservas = true
    @AppStorage(ClaveAviso.planes) private var planes = true
    @AppStorage(ClaveAviso.fechas) private var fechas = true
    @AppStorage(ClaveAviso.maleta) private var maleta = true

    var body: some View {
        Section {
            Toggle("Avisos en este iPhone", isOn: $activados)
            if activados {
                if avisos.permiso == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Los avisos están bloqueados. Toca para activarlos en Ajustes de iOS.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Toggle("⏳ Cuenta atrás (7 días y 1 día antes)", isOn: $cuentaAtras)
                Toggle("✈️ Vuelos, trenes y check-in", isOn: $reservas)
                Toggle("📍 Planes del día", isOn: $planes)
                Toggle("🧳 Maleta pendiente", isOn: $maleta)
                Toggle("💝 Fechas especiales", isOn: $fechas)
            }
        } header: {
            Text("Avisos")
        } footer: {
            Text("Cada uno elige sus avisos en su iPhone. Nunca destapan el destino de una sorpresa.")
        }
        .onChange(of: [activados, cuentaAtras, reservas, planes, fechas, maleta]) { _, _ in
            Task { await avisos.reprogramar(almacen: almacen, miId: sesion.miId) }
        }
        .task { await avisos.actualizarPermiso() }
    }
}
