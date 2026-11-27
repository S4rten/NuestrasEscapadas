import SwiftUI
import UIKit

// ============================================================================
// PASAR AL PLAN: una idea (o una opción de actividad) pasa a un día del
// itinerario, sin hora fija. Si ya está en el plan, se ve el día y se puede
// mover a otro (conservando la hora si la tenía).
// ============================================================================

enum PlanDesdeTexto {
    /// Separa el nombre y el enlace de un texto ("📍 Coliseo", "Cena en https://…").
    static func nombreYEnlace(_ texto: String) -> (nombre: String, enlace: String) {
        var limpio = texto.recortado
        if limpio.hasPrefix("📍") {
            limpio = String(limpio.dropFirst()).recortado
        }
        var enlace = ""
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
           let m = detector.firstMatch(in: limpio, range: NSRange(limpio.startIndex..., in: limpio)),
           let url = m.url,
           let rango = Range(m.range, in: limpio) {
            enlace = url.absoluteString
            limpio = limpio.replacingCharacters(in: rango, with: "").recortado
            if limpio.isEmpty {
                let host = URLComponents(url: url, resolvingAgainstBaseURL: false)?.host ?? enlace
                limpio = host.replacingOccurrences(of: "www.", with: "")
            }
        }
        return (limpio, enlace)
    }

    /// El plan de esta escapada que tiene ese nombre (si ya se pasó al plan).
    @MainActor
    static func actividad(nombre: String, escapada: Escapada, almacen: Almacen) -> Actividad? {
        let n = HorarioOSM.normalizar(nombre)
        guard !n.isEmpty else { return nil }
        return almacen.actividadesDe(escapada.id).first { HorarioOSM.normalizar($0.nombreSitio) == n }
    }
}

/// Botón "📅 Al plan" con los días del viaje.
struct MenuAlPlan: View {
    @EnvironmentObject var almacen: Almacen
    let escapada: Escapada
    let texto: String
    /// Enlace aparte (el de una opción), por si el texto no lo lleva.
    var enlaceExtra: String = ""

    var body: some View {
        let datos = PlanDesdeTexto.nombreYEnlace(texto)
        let existente = PlanDesdeTexto.actividad(nombre: datos.nombre, escapada: escapada, almacen: almacen)
        let enPlan = existente != nil

        Menu {
            Section(enPlan ? "Mover al día…" : "¿Qué día lo hacéis?") {
                ForEach(1...escapada.totalDias, id: \.self) { d in
                    Button {
                        elegir(dia: d, existente: existente, nombre: datos.nombre, enlace: datos.enlace)
                    } label: {
                        Text(etiqueta(d, actual: existente?.dia))
                    }
                }
            }
        } label: {
            Label(existente.map { "En el plan · día \($0.dia)" } ?? "Al plan",
                  systemImage: enPlan ? "calendar" : "calendar.badge.plus")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(enPlan ? Color.green : Color.accentColor)
                .background((enPlan ? Color.green : Color.accentColor).opacity(0.15))
                .clipShape(Capsule())
        }
        .disabled(datos.nombre.isEmpty)
    }

    private func etiqueta(_ d: Int, actual: Int?) -> String {
        let fecha = escapada.fechaParaDia(d).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        return "Día \(d) · \(fecha)\(actual == d ? " ✓" : "")"
    }

    private func elegir(dia: Int, existente: Actividad?, nombre: String, enlace: String) {
        if let a = existente {
            if a.dia != dia {
                Ambiente.mover(a, aDia: dia, escapada: escapada, almacen: almacen)
            }
            return
        }
        var a = Actividad()
        a.escapadaId = escapada.id
        a.dia = dia
        a.nombreSitio = nombre
        a.urlSitio = enlace.isEmpty ? enlaceExtra.recortado : enlace
        a.hora = nil                        // sin hora fija: ya se la pondréis en el Plan
        a.creadaEn = Date()
        almacen.guardar(a, en: .actividades)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
