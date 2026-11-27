import SwiftUI

// ============================================================================
// PONER O CAMBIAR LA HORA DE UN PLAN
// Para los planes que se añadieron sin hora (por ejemplo, desde las ideas):
// cuando ya sabéis a qué hora vais, se la ponéis aquí. También sirve para
// cambiarla, quitarla, marcar "todo el día" o moverlo a otro día.
// ============================================================================

struct FormularioHoraPlan: View {
    @EnvironmentObject var almacen: Almacen
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var horarios = ServicioHorarios.compartido
    @ObservedObject private var festivos = ServicioFestivos.compartido

    let actividad: Actividad
    let escapada: Escapada

    @State private var dia: Int
    @State private var hora: Date
    @State private var todoElDia: Bool

    init(actividad: Actividad, escapada: Escapada) {
        self.actividad = actividad
        self.escapada = escapada
        _dia = State(initialValue: min(max(actividad.dia, 1), escapada.totalDias))
        _hora = State(initialValue: actividad.hora ?? Date().conHora(10))
        _todoElDia = State(initialValue: actividad.todoElDia)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(actividad.nombreSitio)
                        .font(.headline)
                    if let h = actividad.hora, !actividad.todoElDia {
                        Text("Ahora: a las \(h.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !actividad.todoElDia {
                        Text("Ahora: sin hora fija")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if escapada.totalDias > 1 {
                        Picker("Día", selection: $dia) {
                            ForEach(1...escapada.totalDias, id: \.self) { d in
                                Text("Día \(d) · \(escapada.fechaParaDia(d).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                                    .tag(d)
                            }
                        }
                    }

                    Toggle("Ocupa todo el día", isOn: $todoElDia)

                    if !todoElDia {
                        DatePicker("Hora", selection: $hora, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                    }

                    if let aviso = avisoApertura {
                        Text(aviso)
                            .font(.caption)
                            .foregroundStyle(aviso.hasPrefix("⚠️") ? Color.orange : Color.secondary)
                    }
                } header: {
                    Text("¿Cuándo?")
                }

                let otros = otrosPlanes
                if !otros.isEmpty {
                    Section("Ese día ya tenéis") {
                        ForEach(otros) { e in
                            HStack(spacing: 10) {
                                Text(e.hora.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 48, alignment: .leading)
                                Text("\(e.icono) \(e.titulo)")
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if actividad.hora != nil && !actividad.todoElDia {
                    Section {
                        Button(role: .destructive) {
                            quitarHora()
                        } label: {
                            Label("Quitar la hora (sin hora fija)", systemImage: "clock.badge.xmark")
                        }
                    }
                }
            }
            .navigationTitle(actividad.hora == nil && !actividad.todoElDia ? "Poner hora" : "Cambiar hora")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                }
            }
        }
    }

    /// Lo que ya hay ese día con hora (sin este plan), para elegir una hora que encaje.
    private var otrosPlanes: [EventoLinea] {
        almacen.eventos(de: escapada, dia: dia).filter { e in
            e.actividadId != actividad.id && (e.hora != nil || e.todoElDia)
        }
    }

    /// Horario de apertura de ese día (si se conoce) y aviso si a la hora elegida está cerrado.
    private var avisoApertura: String? {
        guard let h = horarios.horario(de: actividad), !h.horario.isEmpty else { return nil }
        let fecha = escapada.fechaParaDia(dia)
        let esFestivo = festivos.festivo(pais: escapada.paisCodigo.uppercased(), fecha: fecha) != nil
        switch HorarioOSM.estado(h.horario, fecha: fecha, esFestivo: esFestivo) {
        case .cerrado:
            return "⚠️ Ese día está cerrado\(esFestivo ? " (es festivo)" : "") según OpenStreetMap."
        case .abierto(let tramos):
            let texto = HorarioOSM.textoAbierto(tramos)
            guard !todoElDia else { return "🕐 \(texto)" }
            let c = Calendar.current.dateComponents([.hour, .minute], from: hora)
            let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            let abierto = tramos.contains { $0.contains(m) || $0.contains(m + 1440) }
            return abierto ? "🕐 \(texto)" : "⚠️ A esa hora está cerrado (\(texto.lowercased()))."
        case .desconocido:
            return "🕐 \(HorarioOSM.traducir(h.horario))"
        }
    }

    private func guardar() {
        var campos: [String: Any] = [:]
        if dia != actividad.dia { campos["dia"] = dia }
        if todoElDia {
            campos["todoElDia"] = true
            campos["hora"] = NSNull()
        } else {
            campos["todoElDia"] = false
            campos["hora"] = escapada.fechaParaDia(dia).combinando(horaDe: hora)
        }
        almacen.actualizar(actividad.id, en: .actividades, campos: campos)
        dismiss()
    }

    private func quitarHora() {
        var campos: [String: Any] = ["hora": NSNull(), "todoElDia": false]
        if dia != actividad.dia { campos["dia"] = dia }
        almacen.actualizar(actividad.id, en: .actividades, campos: campos)
        dismiss()
    }
}
