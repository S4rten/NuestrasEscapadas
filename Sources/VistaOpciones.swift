import SwiftUI

// ============================================================================
// PESTAÑA OPCIONES: comparador antes de reservar. Apuntáis 2-3 candidatos
// (hoteles, vuelos…) con precio y enlace, votáis, y el elegido pasa a
// Reservas con un toque.
// ============================================================================

struct OpcionesSecciones: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    let escapada: Escapada
    @Binding var hoja: HojaDetalle?

    @State private var titulo = ""
    @State private var tipo: TipoOpcion = .alojamiento
    @State private var precioTexto = ""
    @State private var enlace = ""
    @State private var editando: Opcion? = nil
    @State private var borrando: Opcion? = nil

    private func numero(_ texto: String) -> Double {
        Double(texto.recortado.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var body: some View {
        let todas = almacen.opcionesDe(escapada.id)

        Section {
            Picker("Tipo", selection: $tipo) {
                ForEach(TipoOpcion.allCases) { t in
                    Text("\(t.emoji) \(t.nombre)").tag(t)
                }
            }

            TextField("Nombre (ej: Hotel Roma Centro)", text: $titulo)
                .sheet(item: $editando) { o in
                    FormularioOpcion(opcion: o)
                }

            TextField("Precio total en € (opcional)", text: $precioTexto)
                .keyboardType(.decimalPad)

            TextField("Enlace (Booking, Skyscanner…)", text: $enlace)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button {
                anadir()
            } label: {
                Label("Añadir opción", systemImage: "plus.circle.fill")
            }
            .disabled(titulo.recortado.isEmpty)
        } header: {
            Text("Nueva opción")
        } footer: {
            if todas.isEmpty {
                Text("Apuntad aquí los candidatos antes de reservar, votad 👍/👎 y elegid uno. Los hoteles, vuelos y trenes pasan a Reservas con «Añadir a Reservas», y las actividades al Plan con «Al plan».")
            }
        }

        ForEach(TipoOpcion.allCases) { t in
            let delTipo = todas.filter { $0.tipoOpcion == t }
            if !delTipo.isEmpty {
                seccion(t, delTipo)
            }
        }
    }

    // MARK: Sección por tipo

    @ViewBuilder
    private func seccion(_ t: TipoOpcion, _ lista: [Opcion]) -> some View {
        let ordenadas = lista.sorted { a, b in
            if a.elegida != b.elegida { return a.elegida }
            let pa = puntuacion(a.votos), pb = puntuacion(b.votos)
            if pa != pb { return pa > pb }
            if a.precio != b.precio {
                if a.precio == 0 { return false }
                if b.precio == 0 { return true }
                return a.precio < b.precio
            }
            return a.creadoEn < b.creadoEn
        }
        let conPrecio = lista.filter { $0.precio > 0 }
        let masBarata = conPrecio.count > 1 ? conPrecio.min { $0.precio < $1.precio } : nil

        Section {
            ForEach(ordenadas) { o in
                fila(o, masBarata: masBarata)
            }
        } header: {
            Text("\(t.emoji) \(t.nombre) · \(lista.count)")
        } footer: {
            if lista.count > 1, !lista.contains(where: { $0.elegida }) {
                Text("Mantén pulsada una opción para elegirla.")
            }
        }
        .confirmationDialog("¿Borrar esta opción?", isPresented: Binding(
            get: { borrando != nil && borrando?.tipoOpcion == t },
            set: { if !$0 { borrando = nil } }
        ), titleVisibility: .visible) {
            Button("Borrar", role: .destructive) {
                if let o = borrando { almacen.borrar(id: o.id, de: .opciones) }
                borrando = nil
            }
            Button("Cancelar", role: .cancel) { borrando = nil }
        }
    }

    private func fila(_ o: Opcion, masBarata: Opcion?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(o.titulo)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(o.elegida ? Color.green : Color.primary)
                Spacer()
                if o.precio > 0 {
                    Text(o.precio.formatoDivisa())
                        .font(.subheadline.bold().monospacedDigit())
                }
            }

            HStack(spacing: 6) {
                if o.elegida {
                    Chip(texto: "✅ Elegida", color: .green)
                }
                if let barata = masBarata {
                    if barata.id == o.id {
                        Chip(texto: "💰 La más barata", color: .orange)
                    } else if o.precio > 0 {
                        Chip(texto: "+\((o.precio - barata.precio).formatoDivisa())", color: .gray)
                    }
                }
                if o.creadoPorId != sesion.miId && !o.creadoPorId.isEmpty {
                    Text("de \(almacen.nombre(de: o.creadoPorId, miId: sesion.miId))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !o.notas.isEmpty {
                Text(o.notas)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                BotonesVoto(coleccion: .opciones, id: o.id, votos: o.votos)
                Spacer(minLength: 0)
                if let url = urlDesdeTexto(o.enlace) {
                    BotonEnlace(titulo: "Ver", url: url)
                }
            }

            // Pasarla a Reservas (alojamientos, vuelos, trenes) o al Plan (actividades).
            if o.tipoOpcion.vaAReservas {
                if estaEnReservas(o) {
                    Text("✅ Ya está en Reservas › \(apartadoReservas(o.tipoOpcion))")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                } else {
                    Button {
                        pasarAReservas(o)
                    } label: {
                        Label("Añadir a Reservas › \(apartadoReservas(o.tipoOpcion))", systemImage: "ticket")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if o.tipoOpcion == .actividad {
                MenuAlPlan(escapada: escapada, texto: o.titulo, enlaceExtra: o.enlace)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if o.elegida {
                Button {
                    almacen.elegirOpcion(o, elegida: false)
                } label: {
                    Label("Quitar como elegida", systemImage: "xmark.circle")
                }
            } else {
                Button {
                    almacen.elegirOpcion(o, elegida: true)
                } label: {
                    Label("Elegir esta", systemImage: "checkmark.seal")
                }
            }
            if o.tipoOpcion.vaAReservas {
                Button {
                    pasarAReservas(o)
                } label: {
                    Label("Elegir y pasar a Reservas", systemImage: "ticket")
                }
            }
            Button {
                editando = o
            } label: {
                Label("Editar", systemImage: "pencil")
            }
            Button(role: .destructive) {
                borrando = o
            } label: {
                Label("Borrar", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            if !o.elegida {
                Button {
                    if o.tipoOpcion.vaAReservas {
                        pasarAReservas(o)
                    } else {
                        almacen.elegirOpcion(o, elegida: true)
                    }
                } label: {
                    Label("Elegir", systemImage: "checkmark.seal.fill")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                borrando = o
            } label: {
                Label("Borrar", systemImage: "trash")
            }
        }
    }

    // MARK: Lógica

    private func anadir() {
        let nombre = titulo.recortado
        guard !nombre.isEmpty else { return }
        var o = Opcion()
        o.escapadaId = escapada.id
        o.tipo = tipo.rawValue
        o.titulo = nombre
        o.precio = max(0, numero(precioTexto))
        o.enlace = enlace.recortado
        o.creadoPorId = sesion.miId
        o.creadoEn = Date()
        almacen.guardar(o, en: .opciones)
        titulo = ""
        precioTexto = ""
        enlace = ""
    }

    /// Nombre del apartado de Reservas donde va cada tipo.
    private func apartadoReservas(_ t: TipoOpcion) -> String {
        switch t {
        case .alojamiento: return "Alojamiento"
        case .vuelo: return "Vuelos"
        case .tren: return "Trenes"
        default: return ""
        }
    }

    /// ¿Ya se pasó esta opción a Reservas? (mismo nombre o mismo enlace)
    private func estaEnReservas(_ o: Opcion) -> Bool {
        let nombre = HorarioOSM.normalizar(o.titulo)
        let enlace = o.enlace.recortado
        switch o.tipoOpcion {
        case .alojamiento:
            return almacen.alojamientosDe(escapada.id).contains {
                HorarioOSM.normalizar($0.nombre) == nombre || (!enlace.isEmpty && $0.urlReserva == enlace)
            }
        case .vuelo:
            return almacen.vuelosDe(escapada.id).contains {
                HorarioOSM.normalizar($0.aerolinea) == nombre || (!enlace.isEmpty && $0.urlReserva == enlace)
            }
        case .tren:
            return !enlace.isEmpty && almacen.trenesDe(escapada.id).contains { $0.urlReserva == enlace }
        default:
            return false
        }
    }

    /// Marca la opción como elegida y abre el formulario de la reserva ya relleno.
    private func pasarAReservas(_ o: Opcion) {
        almacen.elegirOpcion(o, elegida: true)
        switch o.tipoOpcion {
        case .alojamiento:
            var a = Alojamiento()
            a.escapadaId = escapada.id
            a.nombre = o.titulo
            a.urlReserva = o.enlace
            a.entrada = escapada.fechaInicio.conHora(15)
            a.salida = escapada.fechaFin.conHora(11)
            hoja = .alojamiento(a)
        case .vuelo:
            var v = Vuelo()
            v.escapadaId = escapada.id
            v.aerolinea = o.titulo
            v.urlReserva = o.enlace
            v.fechaHoraSalida = escapada.fechaInicio.conHora(9)
            v.fechaHoraLlegada = v.fechaHoraSalida.addingTimeInterval(9000)
            hoja = .vuelo(v)
        case .tren:
            var t = TrenViaje()
            t.escapadaId = escapada.id
            t.urlReserva = o.enlace
            t.fechaHoraSalida = escapada.fechaInicio.conHora(9)
            t.fechaHoraLlegada = t.fechaHoraSalida.addingTimeInterval(9000)
            hoja = .tren(t)
        default:
            break
        }
    }
}

// ============================================================================
// EDITAR UNA OPCIÓN (sin tocar los votos)
// ============================================================================

struct FormularioOpcion: View {
    @EnvironmentObject var almacen: Almacen
    @Environment(\.dismiss) private var dismiss

    let opcion: Opcion
    @State private var titulo: String
    @State private var tipo: TipoOpcion
    @State private var precioTexto: String
    @State private var enlace: String
    @State private var notas: String

    init(opcion: Opcion) {
        self.opcion = opcion
        _titulo = State(initialValue: opcion.titulo)
        _tipo = State(initialValue: opcion.tipoOpcion)
        _precioTexto = State(initialValue: opcion.precio > 0 ? String(format: "%.2f", opcion.precio) : "")
        _enlace = State(initialValue: opcion.enlace)
        _notas = State(initialValue: opcion.notas)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Opción") {
                    Picker("Tipo", selection: $tipo) {
                        ForEach(TipoOpcion.allCases) { t in
                            Text("\(t.emoji) \(t.nombre)").tag(t)
                        }
                    }
                    TextField("Nombre", text: $titulo)
                    TextField("Precio total en €", text: $precioTexto)
                        .keyboardType(.decimalPad)
                    TextField("Enlace", text: $enlace)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Notas") {
                    TextField("Ej: desayuno incluido, cancelación gratis…", text: $notas, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Editar opción")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let precio = Double(precioTexto.recortado.replacingOccurrences(of: ",", with: ".")) ?? 0
                        almacen.actualizar(opcion.id, en: .opciones, campos: [
                            "titulo": titulo.recortado,
                            "tipo": tipo.rawValue,
                            "precio": max(0, precio),
                            "enlace": enlace.recortado,
                            "notas": notas.recortado
                        ])
                        dismiss()
                    }
                    .disabled(titulo.recortado.isEmpty)
                }
            }
        }
    }
}
