import SwiftUI

// ============================================================================
// PRESUPUESTO Y GASTOS POR DÍA
//  · SeccionPresupuesto:   barra de lo gastado frente al presupuesto (pestaña Gastos)
//  · SeccionGastosPorDia:  desglose del total por cada día del viaje (pestaña Gastos)
//  · SeccionGastosDelDia:  gastos del día elegido en el itinerario (pestaña Plan)
// Los gastos se asignan a un día según su fecha.
// ============================================================================

struct SeccionPresupuesto: View {
    let escapada: Escapada
    let gastado: Double
    @Binding var hoja: HojaDetalle?

    var body: some View {
        if escapada.tienePresupuesto {
            let restante = escapada.presupuesto - gastado
            let proporcion = escapada.presupuesto > 0 ? gastado / escapada.presupuesto : 0

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PRESUPUESTO")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text(escapada.presupuesto.formatoDivisa())
                                .font(.title3.bold().monospacedDigit())
                        }
                        Spacer()
                        Text(restante >= 0
                             ? "Quedan \(restante.formatoDivisa())"
                             : "Os habéis pasado \((-restante).formatoDivisa())")
                            .font(.caption.bold())
                            .foregroundStyle(colorBarra(proporcion))
                    }

                    ProgressView(value: min(max(proporcion, 0), 1))
                        .tint(colorBarra(proporcion))

                    HStack {
                        Text("Gastado: \(gastado.formatoDivisa())")
                        Spacer()
                        Text("\(Int((proporcion * 100).rounded())) %")
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } footer: {
                if escapada.presupuestoEditable {
                    Text("Podéis cambiar el presupuesto desde «Editar escapada» hasta el día antes de salir.")
                }
            }
        } else if escapada.presupuestoEditable {
            Section {
                Button {
                    hoja = .editar
                } label: {
                    Label("Definir un presupuesto para el viaje", systemImage: "banknote")
                }
            }
        }
    }

    private func colorBarra(_ proporcion: Double) -> Color {
        if proporcion > 1 { return .red }
        if proporcion > 0.8 { return .orange }
        return .green
    }
}

struct SeccionGastosPorDia: View {
    let escapada: Escapada
    let gastos: [Gasto]

    var body: some View {
        let fuera = gastos.filter { escapada.diaDelViaje(para: $0.fecha) == nil }
        let totalFuera = fuera.reduce(0) { $0 + $1.importe }
        let mediaDiaria = escapada.tienePresupuesto ? escapada.presupuesto / Double(escapada.totalDias) : 0

        Section {
            ForEach(1...escapada.totalDias, id: \.self) { dia in
                let delDia = gastos.filter { escapada.diaDelViaje(para: $0.fecha) == dia }
                let total = delDia.reduce(0) { $0 + $1.importe }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Día \(dia)")
                            .font(.subheadline.weight(.medium))
                        Text("\(escapada.fechaParaDia(dia).formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) · \(delDia.count) \(delDia.count == 1 ? "gasto" : "gastos")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(total.formatoDivisa())
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(mediaDiaria > 0 && total > mediaDiaria ? Color.orange : Color.primary)
                }
            }

            if !fuera.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Antes o fuera del viaje")
                            .font(.subheadline.weight(.medium))
                        Text("Reservas, billetes… · \(fuera.count) \(fuera.count == 1 ? "gasto" : "gastos")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(totalFuera.formatoDivisa())
                        .font(.subheadline.bold().monospacedDigit())
                }
            }
        } header: {
            Text("Gastado por días")
        } footer: {
            if mediaDiaria > 0 {
                Text("En naranja, los días que superan el presupuesto medio por día (\(mediaDiaria.formatoDivisa())).")
            }
        }
    }
}

struct SeccionGastosDelDia: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    let escapada: Escapada
    let dia: Int
    @Binding var hoja: HojaDetalle?

    var body: some View {
        let todos = almacen.gastosDe(escapada.id)
        let delDia = todos.filter { escapada.diaDelViaje(para: $0.fecha) == dia }
        let totalDia = delDia.reduce(0) { $0 + $1.importe }
        let totalViaje = todos.reduce(0) { $0 + $1.importe }

        Section {
            ForEach(delDia) { gasto in
                HStack(spacing: 10) {
                    Text(CategoriaGasto.icono(para: gasto.categoria))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(gasto.concepto)
                            .font(.subheadline)
                        Text("Pagó \(gasto.pagadoPorId == sesion.miId ? sesion.miNombre : almacen.nombre(de: gasto.pagadoPorId, miId: sesion.miId))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(gasto.importe.formatoDivisa())
                        .font(.subheadline.bold().monospacedDigit())
                }
                .contentShape(Rectangle())
                .onTapGesture { hoja = .gasto(gasto) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        almacen.borrar(id: gasto.id, de: .gastos)
                    } label: {
                        Label("Borrar", systemImage: "trash")
                    }
                }
            }

            Button {
                hoja = .gastoEnDia(escapada.fechaParaDia(dia))
            } label: {
                Label("Añadir gasto al día \(dia)", systemImage: "plus.circle.fill")
            }
        } header: {
            HStack {
                Text("Gastos del día \(dia)")
                Spacer()
                Text(totalDia.formatoDivisa())
                    .font(.caption.bold().monospacedDigit())
            }
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total del viaje: \(totalViaje.formatoDivisa())")
                if escapada.tienePresupuesto {
                    let restante = escapada.presupuesto - totalViaje
                    Text(restante >= 0
                         ? "Quedan \(restante.formatoDivisa()) de \(escapada.presupuesto.formatoDivisa())"
                         : "Os habéis pasado \((-restante).formatoDivisa()) del presupuesto")
                }
            }
        }
    }
}
