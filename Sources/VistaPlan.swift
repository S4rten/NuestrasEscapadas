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
    @State private var hora = Date().conHora(11)
    @State private var soloPendientes = false

    /// Si cambian las fechas del viaje, el día seleccionado nunca se sale de rango.
    private var diaActivo: Int {
        min(max(dia, 1), escapada.totalDias)
    }

    var body: some View {
        Section {
            if escapada.totalDias > 1 {
                selectorDias
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            TextField("Sitio o plan (ej: Museo del Prado)", text: $nombre)

            Toggle("Hora fija", isOn: $conHora)
            if conHora {
                DatePicker("Hora", selection: $hora, displayedComponents: .hourAndMinute)
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
                            Text("Día \(d)")
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
                Text(evento.hora.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                    .font(.caption2.bold().monospacedDigit())
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
                if let enlace = evento.enlace {
                    BotonEnlace(titulo: "Abrir enlace", url: enlace)
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
        actividad.hora = conHora ? escapada.fechaParaDia(diaActivo).combinando(horaDe: hora) : nil
        almacen.guardar(actividad, en: .actividades)
        nombre = ""
        url = ""
        conHora = false
    }

    private func construirEventos() -> [EventoLinea] {
        let calendario = Calendar.current
        let fecha = escapada.fechaParaDia(diaActivo)
        var lista: [EventoLinea] = []

        for v in almacen.vuelosDe(escapada.id) where calendario.isDate(v.fechaHoraSalida, inSameDayAs: fecha) {
            let detalles = [v.aerolinea, v.numeroVuelo, v.terminalPuerta].filter { !$0.isEmpty }
            lista.append(EventoLinea(
                id: "vuelo-\(v.id)",
                hora: v.fechaHoraSalida,
                titulo: "\(v.origen) → \(v.destino)",
                subtitulo: detalles.joined(separator: " · "),
                icono: "✈️",
                actividadId: nil,
                completada: false,
                enlace: urlDesdeTexto(v.urlReserva)
            ))
        }

        for t in almacen.trenesDe(escapada.id) where calendario.isDate(t.fechaHoraSalida, inSameDayAs: fecha) {
            lista.append(EventoLinea(
                id: "tren-\(t.id)",
                hora: t.fechaHoraSalida,
                titulo: "\(t.estacionOrigen) → \(t.estacionDestino)",
                subtitulo: "\(t.operadora) · \(t.trayecto)",
                icono: "🚂",
                actividadId: nil,
                completada: false,
                enlace: urlDesdeTexto(t.urlReserva)
            ))
        }

        for a in almacen.alojamientosDe(escapada.id) {
            let nombreAloj = a.nombre.isEmpty ? "Alojamiento" : a.nombre
            if calendario.isDate(a.entrada, inSameDayAs: fecha) {
                lista.append(EventoLinea(
                    id: "entrada-\(a.id)",
                    hora: a.entrada,
                    titulo: "Check-in: \(nombreAloj)",
                    subtitulo: a.direccion,
                    icono: "🔑",
                    actividadId: nil,
                    completada: false,
                    enlace: urlDesdeTexto(a.urlReserva)
                ))
            }
            if calendario.isDate(a.salida, inSameDayAs: fecha) {
                lista.append(EventoLinea(
                    id: "salida-\(a.id)",
                    hora: a.salida,
                    titulo: "Check-out: \(nombreAloj)",
                    subtitulo: a.direccion,
                    icono: "🧳",
                    actividadId: nil,
                    completada: false,
                    enlace: urlDesdeTexto(a.urlReserva)
                ))
            }
        }

        for actividad in almacen.actividadesDe(escapada.id) where actividad.dia == diaActivo {
            lista.append(EventoLinea(
                id: "actividad-\(actividad.id)",
                hora: actividad.hora,
                titulo: actividad.nombreSitio,
                subtitulo: actividad.hora == nil ? "Sin hora fija" : "Plan del día",
                icono: "📍",
                actividadId: actividad.id,
                completada: actividad.completada,
                enlace: urlDesdeTexto(actividad.urlSitio)
            ))
        }

        return lista.sorted { a, b in
            switch (a.hora, b.hora) {
            case let (x?, y?):
                return x < y
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return a.titulo < b.titulo
            }
        }
    }
}
