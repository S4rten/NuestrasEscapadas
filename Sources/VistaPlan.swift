import SwiftUI

// ============================================================================
// PESTAÑA PLAN: itinerario por días con línea del tiempo
// (reúne vuelos, trenes, check-in/out y las actividades que vais añadiendo)
// ============================================================================

struct PlanSecciones: View {
    @EnvironmentObject var almacen: Almacen
    let escapada: Escapada
    @Binding var hoja: HojaDetalle?

    @State private var dia = 1
    @State private var nombre = ""
    @State private var url = ""
    @State private var conHora = false
    @State private var todoElDia = false
    @State private var hora = Date().conHora(11)
    @State private var soloPendientes = false

    /// Modo "Hoy": si estáis de viaje, el Plan se abre directamente en el día de hoy.
    init(escapada: Escapada, hoja: Binding<HojaDetalle?>) {
        self.escapada = escapada
        self._hoja = hoja
        self._dia = State(initialValue: escapada.diaDeHoy ?? 1)
    }

    /// Si cambian las fechas del viaje, el día seleccionado nunca se sale de rango.
    private var diaActivo: Int {
        min(max(dia, 1), escapada.totalDias)
    }

    var body: some View {
        if escapada.diaDeHoy == diaActivo {
            SeccionAhora(escapada: escapada)
        }

        SeccionTiempoDia(escapada: escapada, dia: diaActivo)

        Section {
            if escapada.totalDias > 1 {
                selectorDias
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            TextField("Sitio o plan (ej: Museo del Prado)", text: $nombre)

            Toggle("Ocupa todo el día", isOn: $todoElDia)
            if !todoElDia {
                Toggle("Hora fija", isOn: $conHora)
                if conHora {
                    DatePicker("Hora", selection: $hora, displayedComponents: .hourAndMinute)
                }
            }

            TextField("Enlace opcional", text: $url)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                anadir()
            } label: {
                Label("Añadir al día \(diaActivo)", systemImage: "plus.circle.fill")
            }
            .disabled(nombre.recortado.isEmpty)
        } header: {
            Text(escapada.totalDias > 1 ? "Añadir al día \(diaActivo)" : "Añadir un plan")
        } footer: {
            Text("«Ocupa todo el día» es para planes como un parque de atracciones o una excursión: se queda fijo arriba del día.")
        }

        Section {
            let eventos = construirEventos()
            let visibles = soloPendientes ? eventos.filter { !$0.completada } : eventos

            if eventos.isEmpty {
                Text("Aún no hay nada planeado para el día \(diaActivo).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if visibles.isEmpty {
                Text("¡Todo hecho por hoy! 🎉")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibles) { evento in
                    fila(evento)
                }
            }
        } header: {
            HStack {
                Text("Línea del tiempo · Día \(diaActivo)")
                Spacer()
                Button {
                    soloPendientes.toggle()
                } label: {
                    Text(soloPendientes ? "Ver todos" : "Solo pendientes")
                        .font(.caption2.bold())
                }
            }
        }

        SeccionGastosDelDia(escapada: escapada, dia: diaActivo, hoja: $hoja)
    }

    // MARK: Selector de día

    private var selectorDias: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(1...escapada.totalDias, id: \.self) { d in
                    let activo = diaActivo == d
                    Button {
                        dia = d
                    } label: {
                        VStack(spacing: 2) {
                            Text(escapada.diaDeHoy == d ? "Hoy" : "Día \(d)")
                                .font(.caption.bold())
                            Text(escapada.fechaParaDia(d).formatted(.dateTime.day().month(.abbreviated)))
                                .font(.caption2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(activo ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                        .foregroundStyle(activo ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: Fila de la línea del tiempo

    private func fila(_ evento: EventoLinea) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                Text(evento.todoElDia ? "Todo\nel día" : (evento.hora.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—"))
                    .font(.caption2.bold().monospacedDigit())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(evento.completada ? Color.secondary : Color.accentColor)
                Circle()
                    .fill(evento.completada ? Color.green : Color.accentColor)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(evento.icono) \(evento.titulo)")
                    .font(.subheadline.weight(.medium))
                    .strikethrough(evento.completada)
                    .foregroundStyle(evento.completada ? Color.secondary : Color.primary)
                if !evento.subtitulo.isEmpty {
                    Text(evento.subtitulo)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if evento.enlace != nil || evento.ruta != nil {
                    HStack(spacing: 6) {
                        if let enlace = evento.enlace {
                            BotonEnlace(titulo: "Abrir enlace", url: enlace)
                        }
                        if let ruta = evento.ruta {
                            BotonEnlace(titulo: "Cómo llegar", url: ruta, icono: "map.fill")
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if let actividadId = evento.actividadId {
                Button {
                    almacen.actualizar(actividadId, en: .actividades, campos: ["completada": !evento.completada])
                } label: {
                    Image(systemName: evento.completada ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(evento.completada ? Color.green : Color.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .listRowBackground(evento.todoElDia ? Color.accentColor.opacity(0.12) : nil)
        .swipeActions(edge: .leading) {
            if let actividadId = evento.actividadId {
                Button {
                    almacen.actualizar(actividadId, en: .actividades, campos: ["todoElDia": !evento.todoElDia])
                } label: {
                    Label(evento.todoElDia ? "Quitar todo el día" : "Todo el día", systemImage: "sun.max.fill")
                }
                .tint(.orange)
            }
        }
        .swipeActions(edge: .trailing) {
            if let actividadId = evento.actividadId {
                Button(role: .destructive) {
                    almacen.borrar(id: actividadId, de: .actividades)
                } label: {
                    Label("Borrar", systemImage: "trash")
                }
            }
        }
    }

    // MARK: Lógica

    private func anadir() {
        let sitio = nombre.recortado
        guard !sitio.isEmpty else { return }
        var actividad = Actividad()
        actividad.escapadaId = escapada.id
        actividad.dia = diaActivo
        actividad.nombreSitio = sitio
        actividad.urlSitio = url.recortado
        actividad.todoElDia = todoElDia
        actividad.hora = (conHora && !todoElDia) ? escapada.fechaParaDia(diaActivo).combinando(horaDe: hora) : nil
        almacen.guardar(actividad, en: .actividades)
        nombre = ""
        url = ""
        conHora = false
        todoElDia = false
    }

    private func construirEventos() -> [EventoLinea] {
        // Lógica compartida con el modo "Hoy" e Inicio (ver VistaHoy.swift).
        almacen.eventos(de: escapada, dia: diaActivo)
    }
}
