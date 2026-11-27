import SwiftUI

// ============================================================================
// ESTADO DEL VUELO EL MISMO DÍA (AeroDataBox, con la clave de horarios)
// Solo se consulta el día del vuelo y como mucho una vez por hora (cada 10 min
// si se pide a mano), para no gastar las búsquedas gratis del mes.
// Sin servidor propio, se actualiza mientras la app está abierta.
// ============================================================================

struct EstadoVuelo: Codable, Equatable {
    var estado: String = ""                 // Expected, Delayed, Canceled, Departed, Arrived…
    var programada: Date? = nil             // salida programada (instante exacto)
    var salidaPrevista: Date? = nil         // salida revisada
    var llegadaPrevista: Date? = nil
    var terminal: String = ""
    var puerta: String = ""
    var terminalLlegada: String = ""
    var cinta: String = ""
    var consultadoEn: Date = Date()

    /// Minutos de retraso de la salida (0 si va en hora o no se sabe).
    var retrasoMinutos: Int {
        guard let p = programada, let r = salidaPrevista else { return 0 }
        return max(0, Int((r.timeIntervalSince(p) / 60).rounded()))
    }

    var cancelado: Bool { estado.lowercased().hasPrefix("cancel") }

    var conRetraso: Bool { !cancelado && (retrasoMinutos >= 15 || estado == "Delayed") }

    var textoEstado: String {
        switch estado {
        case "Expected", "Unknown", "": return conRetraso ? "Con retraso" : "Previsto en hora"
        case "CheckIn": return "Facturación abierta"
        case "Boarding": return "Embarcando"
        case "GateClosed": return "Puerta cerrada"
        case "Delayed": return "Con retraso"
        case "Departed", "EnRoute": return "En el aire"
        case "Approaching": return "Aterrizando"
        case "Arrived": return "Ha aterrizado"
        case "Canceled", "CanceledUncertain": return "Cancelado"
        case "Diverted": return "Desviado a otro aeropuerto"
        default: return estado
        }
    }

    var icono: String {
        if cancelado || estado == "Diverted" { return "❌" }
        if conRetraso { return "⚠️" }
        switch estado {
        case "Departed", "EnRoute", "Approaching": return "🛫"
        case "Arrived": return "🛬"
        case "Boarding", "GateClosed": return "🚶"
        default: return "✅"
        }
    }
}

@MainActor
final class ServicioEstadoVuelos: ObservableObject {
    static let compartido = ServicioEstadoVuelos()

    @Published private(set) var estados: [String: EstadoVuelo] = [:]    // por ID del vuelo
    @Published private(set) var consultando: Set<String> = []
    @Published private(set) var avisos: [String: String] = [:]          // por ID del vuelo
    private var ultimoIntento: [String: Date] = [:]
    private let claveCache = "escapadas_estado_vuelos_v1"

    init() {
        if let datos = UserDefaults.standard.data(forKey: claveCache),
           let guardados = try? JSONDecoder().decode([String: EstadoVuelo].self, from: datos) {
            // Solo interesan los de las últimas 36 horas.
            estados = guardados.filter { Date().timeIntervalSince($0.value.consultadoEn) < 36 * 3600 }
        }
    }

    /// true si el vuelo sale o llega hoy.
    static func esDeHoy(_ v: Vuelo) -> Bool {
        v.saleElDia(Date())
            || Calendar.current.isDateInToday(v.fechaHoraSalida)
            || Calendar.current.isDateInToday(v.fechaHoraLlegada)
    }

    func actualizar(_ v: Vuelo, clave: String, aMano: Bool = false) async {
        let claveLimpia = clave.recortado
        guard Self.esDeHoy(v), !claveLimpia.isEmpty, v.numeroVuelo.recortado.count >= 3 else { return }
        guard !consultando.contains(v.id) else { return }

        let espera: TimeInterval = aMano ? 10 * 60 : 60 * 60
        if let t = ultimoIntento[v.id], Date().timeIntervalSince(t) < espera { return }
        if let e = estados[v.id], Date().timeIntervalSince(e.consultadoEn) < espera { return }

        ultimoIntento[v.id] = Date()
        consultando.insert(v.id)
        let resultado = await BuscadorVuelos.buscarHorario(
            numeroVuelo: v.numeroVuelo, fecha: v.fechaHoraSalida, clave: claveLimpia, zona: v.zonaDeSalida
        )
        consultando.remove(v.id)

        switch resultado {
        case .encontrados(let lista):
            let origen = v.origen.recortado.uppercased()
            guard let h = lista.first(where: { $0.origen == origen }) ?? lista.first else { return }
            var e = EstadoVuelo()
            e.estado = h.estado
            e.programada = h.salidaExacta
            e.salidaPrevista = h.salidaPrevista
            e.llegadaPrevista = h.llegadaPrevista
            e.terminal = h.terminal
            e.puerta = h.puerta
            e.terminalLlegada = h.terminalLlegada
            e.cinta = h.cinta
            e.consultadoEn = Date()
            estados[v.id] = e
            avisos[v.id] = nil
            guardar()
        case .sinVuelo:
            avisos[v.id] = "Aún no hay datos de este vuelo para hoy."
        case .claveNoValida:
            avisos[v.id] = "La clave de horarios no funciona (revísala en Ajustes)."
        case .limiteAgotado:
            avisos[v.id] = "Se han acabado las búsquedas gratis de este mes."
        case .fallo(let texto):
            avisos[v.id] = texto
        }
    }

    /// Resumen corto para la línea del tiempo: "⚠️ Con retraso (40 min) · Puerta B12".
    func resumen(de v: Vuelo) -> String? {
        guard Self.esDeHoy(v), let e = estados[v.id] else { return nil }
        var principal = "\(e.icono) \(e.textoEstado)"
        if e.conRetraso && e.retrasoMinutos > 0 { principal += " (\(e.retrasoMinutos) min)" }
        var partes = [principal]
        if !e.puerta.isEmpty { partes.append("Puerta \(e.puerta)") }
        if !e.cinta.isEmpty { partes.append("Cinta \(e.cinta)") }
        return partes.joined(separator: " · ")
    }

    private func guardar() {
        if let datos = try? JSONEncoder().encode(estados) {
            UserDefaults.standard.set(datos, forKey: claveCache)
        }
    }
}

/// Recuadro con el estado del vuelo, dentro de la tarjeta del vuelo (solo el día del vuelo).
struct FilaEstadoVuelo: View {
    @EnvironmentObject var almacen: Almacen
    @ObservedObject private var servicio = ServicioEstadoVuelos.compartido
    let vuelo: Vuelo

    var body: some View {
        if ServicioEstadoVuelos.esDeHoy(vuelo) {
            VStack(alignment: .leading, spacing: 4) {
                if almacen.claveVuelos.recortado.isEmpty {
                    Text("Hoy es el vuelo: activa los horarios en Ajustes › Horarios de vuelos para ver retrasos y puerta.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else if let e = servicio.estados[vuelo.id] {
                    Text(lineaPrincipal(e))
                        .font(.caption.bold())
                        .foregroundStyle(e.cancelado ? Color.red : (e.conRetraso ? Color.orange : Color.green))
                    if let detalle = lineaDetalle(e) {
                        Text(detalle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Actualizado \(e.consultadoEn.formatted(.relative(presentation: .named)))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        botonActualizar
                    }
                } else if servicio.consultando.contains(vuelo.id) {
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Mirando el estado del vuelo…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Text(servicio.avisos[vuelo.id] ?? "Toca actualizar para ver si va en hora.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        botonActualizar
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .task(id: vuelo.id) {
                // Mientras se ve la tarjeta, se revisa de vez en cuando (el servicio limita a 1 vez por hora).
                while !Task.isCancelled {
                    await servicio.actualizar(vuelo, clave: almacen.claveVuelos)
                    try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
                }
            }
        }
    }

    private var botonActualizar: some View {
        Button {
            Task { await servicio.actualizar(vuelo, clave: almacen.claveVuelos, aMano: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.caption.bold())
        }
        .buttonStyle(.borderless)
        .disabled(servicio.consultando.contains(vuelo.id))
    }

    private func lineaPrincipal(_ e: EstadoVuelo) -> String {
        if e.cancelado { return "❌ Cancelado: mirad la web o la app de la aerolínea" }
        var texto = "\(e.icono) \(e.textoEstado)"
        if e.conRetraso && e.retrasoMinutos > 0 { texto += " (\(e.retrasoMinutos) min)" }
        if let s = e.salidaPrevista, e.estado != "Departed", e.estado != "EnRoute", e.estado != "Arrived" {
            texto += " · sale a las \(s.hora(en: vuelo.zonaDeSalida))"
        }
        return texto
    }

    private func lineaDetalle(_ e: EstadoVuelo) -> String? {
        var partes: [String] = []
        if !e.terminal.isEmpty { partes.append("Terminal \(e.terminal)") }
        if !e.puerta.isEmpty { partes.append("Puerta \(e.puerta)") }
        if let l = e.llegadaPrevista { partes.append("Llega a las \(l.hora(en: vuelo.zonaDeLlegada))") }
        if !e.terminalLlegada.isEmpty { partes.append("Llegada en T\(e.terminalLlegada)") }
        if !e.cinta.isEmpty { partes.append("Cinta de maletas \(e.cinta)") }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }
}
