import SwiftUI

// ============================================================================
// REPARTO DE GASTOS Y SALDAR CUENTAS
//  · ModoReparto:          a medias, todo de quien paga, todo del otro o personalizado
//  · FilaSaldarCuentas:    botón "Saldar cuentas" que deja el saldo a cero
//  · SeccionPagosPareja:   historial de pagos entre vosotros (no cuentan como gasto)
// ============================================================================

enum ModoReparto: String, CaseIterable, Identifiable {
    case aMedias
    case todoQuienPaga
    case todoElOtro
    case personalizado

    var id: String { rawValue }

    var etiqueta: String {
        switch self {
        case .aMedias: return "A medias"
        case .todoQuienPaga: return "Solo de quien paga"
        case .todoElOtro: return "Todo de la otra persona"
        case .personalizado: return "Personalizado"
        }
    }

    /// Parte de quien paga (0–100). nil = la elige el usuario.
    var porcentaje: Double? {
        switch self {
        case .aMedias: return 50
        case .todoQuienPaga: return 100
        case .todoElOtro: return 0
        case .personalizado: return nil
        }
    }

    static func para(_ porcentaje: Double) -> ModoReparto {
        switch porcentaje {
        case 50: return .aMedias
        case 100: return .todoQuienPaga
        case 0: return .todoElOtro
        default: return .personalizado
        }
    }
}

/// Texto corto para la fila de un gasto que no es a medias.
func textoRepartoCorto(_ porcentajePagador: Double) -> String? {
    switch ModoReparto.para(porcentajePagador) {
    case .aMedias: return nil
    case .todoQuienPaga: return "Solo de quien pagó"
    case .todoElOtro: return "Todo de la otra persona"
    case .personalizado:
        let p = Int(porcentajePagador.rounded())
        return "Reparto \(p) / \(100 - p)"
    }
}

struct FilaSaldarCuentas: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    let escapada: Escapada
    let saldo: Double

    @State private var confirmando = false

    private var parejaId: String? {
        almacen.miembros.first(where: { $0.id != sesion.miId })?.id
    }

    private var pareja: String {
        almacen.nombreDePareja(miId: sesion.miId)
    }

    private var textoConfirmacion: String {
        let cantidad = abs(saldo).formatoDivisa()
        return saldo > 0
            ? "Se apuntará que \(pareja) te ha pagado \(cantidad)."
            : "Se apuntará que le has pagado \(cantidad) a \(pareja)."
    }

    var body: some View {
        if let parejaId = parejaId, abs(saldo) >= 0.01 {
            Button {
                confirmando = true
            } label: {
                Label("Saldar cuentas", systemImage: "checkmark.circle.fill")
            }
            .confirmationDialog("¿Saldar cuentas?", isPresented: $confirmando, titleVisibility: .visible) {
                Button("Sí, ya está pagado") {
                    var pago = PagoPareja()
                    pago.escapadaId = escapada.id
                    // Saldo positivo: tu pareja te debe -> paga tu pareja.
                    pago.deId = saldo > 0 ? parejaId : sesion.miId
                    pago.aId = saldo > 0 ? sesion.miId : parejaId
                    pago.importe = (abs(saldo) * 100).rounded() / 100
                    pago.fecha = Date()
                    almacen.guardar(pago, en: .pagos)
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("\(textoConfirmacion) Quedaréis en paz; no cuenta como gasto del viaje.")
            }
        }
    }
}

struct SeccionPagosPareja: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    let escapada: Escapada

    var body: some View {
        let pagos = almacen.pagosDe(escapada.id)

        if !pagos.isEmpty {
            Section {
                ForEach(pagos) { pago in
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(nombre(pago.deId)) → \(nombre(pago.aId))")
                                .font(.subheadline.weight(.medium))
                            Text(pago.fecha.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(pago.importe.formatoDivisa())
                            .font(.subheadline.bold().monospacedDigit())
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            almacen.borrar(id: pago.id, de: .pagos)
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Pagos entre vosotros")
            } footer: {
                Text("Sirven para saldar cuentas y no suman al total gastado. Desliza para borrar uno si fue un error.")
            }
        }
    }

    private func nombre(_ id: String) -> String {
        id == sesion.miId ? sesion.miNombre : almacen.nombre(de: id, miId: sesion.miId)
    }
}
