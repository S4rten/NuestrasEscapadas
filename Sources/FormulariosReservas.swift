import SwiftUI

// ============================================================================
// FORMULARIOS: vuelo, tren y alojamiento (sirven para crear y para editar)
// ============================================================================

// MARK: - Vuelo

struct FormularioVuelo: View {
    @EnvironmentObject var almacen: Almacen
    @Environment(\.dismiss) private var dismiss

    let escapada: Escapada
    private let esNuevo: Bool

    @State private var vuelo: Vuelo
    @State private var buscando = false
    @State private var mensaje = ""
    @State private var mensajeEsError = false

    init(escapada: Escapada, existente: Vuelo?) {
        self.escapada = escapada
        self.esNuevo = (existente == nil)
        if let existente = existente {
            _vuelo = State(initialValue: existente)
        } else {
            var nuevo = Vuelo()
            nuevo.escapadaId = escapada.id
            nuevo.fechaHoraSalida = escapada.fechaInicio.conHora(9)
            nuevo.fechaHoraLlegada = nuevo.fechaHoraSalida.addingTimeInterval(9000)
            _vuelo = State(initialValue: nuevo)
        }
    }

    private var puedeGuardar: Bool {
        !vuelo.origen.recortado.isEmpty && !vuelo.destino.recortado.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reserva") {
                    Picker("Trayecto", selection: $vuelo.trayecto) {
                        Text("Ida").tag("Ida")
                        Text("Vuelta").tag("Vuelta")
                        Text("Escala").tag("Escala")
                    }
                    TextField("Nº de vuelo (ej: IB3140)", text: $vuelo.numeroVuelo)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Localizador (ej: K8M9LP)", text: $vuelo.localizador)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Aerolínea", text: $vuelo.aerolinea)
                }

                Section {
                    Button {
                        Task { await buscar() }
                    } label: {
                        HStack {
                            if buscando {
                                ProgressView()
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                            Text(buscando ? "Buscando…" : "Sugerir origen y destino por nº de vuelo")
                        }
                    }
                    .disabled(buscando || vuelo.numeroVuelo.recortado.count < 3)

                    if !mensaje.isEmpty {
                        Text(mensaje)
                            .font(.caption)
                            .foregroundStyle(mensajeEsError ? Color.orange : Color.green)
                    }
                } footer: {
                    Text("Opcional. Es solo una sugerencia basada en el número de vuelo: comprueba siempre la ruta con tu billete.")
                }

                Section("Ruta y horarios") {
                    HStack {
                        TextField("Origen (MAD)", text: $vuelo.origen)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("Destino (PRG)", text: $vuelo.destino)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                    }
                    DatePicker("Salida", selection: $vuelo.fechaHoraSalida)
                    DatePicker("Llegada", selection: $vuelo.fechaHoraLlegada)
                    TextField("Terminal / puerta", text: $vuelo.terminalPuerta)
                }

                Section("Enlace") {
                    TextField("URL de check-in o de la reserva", text: $vuelo.urlReserva)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(esNuevo ? "Añadir vuelo" : "Editar vuelo")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: vuelo.trayecto) { _, nuevo in
                guard esNuevo else { return }
                let base = (nuevo == "Vuelta") ? escapada.fechaFin : escapada.fechaInicio
                vuelo.fechaHoraSalida = base.combinando(horaDe: vuelo.fechaHoraSalida)
            }
            .onChange(of: vuelo.fechaHoraSalida) { anterior, nueva in
                // Mantiene la duración del vuelo al cambiar la hora de salida.
                let duracion = vuelo.fechaHoraLlegada.timeIntervalSince(anterior)
                vuelo.fechaHoraLlegada = nueva.addingTimeInterval(duracion > 0 ? duracion : 9000)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(!puedeGuardar)
                }
            }
        }
    }

    private func buscar() async {
        buscando = true
        mensaje = ""
        let ruta = await BuscadorVuelos.buscar(numeroVuelo: vuelo.numeroVuelo)
        buscando = false
        if let ruta = ruta {
            vuelo.origen = ruta.origen
            vuelo.destino = ruta.destino
            if vuelo.aerolinea.recortado.isEmpty && !ruta.aerolinea.isEmpty { vuelo.aerolinea = ruta.aerolinea }
            if vuelo.urlReserva.recortado.isEmpty && !ruta.urlGestion.isEmpty { vuelo.urlReserva = ruta.urlGestion }
            mensajeEsError = false
            mensaje = "Sugerencia: \(ruta.origen) → \(ruta.destino). Compruébala con tu billete."
        } else {
            mensajeEsError = true
            mensaje = "No se encontró ese vuelo. Escribe el origen y el destino a mano."
        }
    }

    private func guardar() {
        var v = vuelo
        v.escapadaId = escapada.id
        v.origen = v.origen.recortado.uppercased()
        v.destino = v.destino.recortado.uppercased()
        v.numeroVuelo = v.numeroVuelo.recortado.uppercased().replacingOccurrences(of: " ", with: "")
        v.localizador = v.localizador.recortado.uppercased()
        v.aerolinea = v.aerolinea.recortado
        v.terminalPuerta = v.terminalPuerta.recortado
        v.urlReserva = v.urlReserva.recortado
        almacen.guardar(v, en: .vuelos)
        dismiss()
    }
}

// MARK: - Tren

private func urlOperadoraTren(_ operadora: String) -> String {
    switch operadora {
    case "Renfe": return "https://www.renfe.com/es/es"
    case "Iryo": return "https://iryo.eu/es"
    case "Ouigo": return "https://www.ouigo.com/es"
    default: return ""
    }
}

struct FormularioTren: View {
    @EnvironmentObject var almacen: Almacen
    @Environment(\.dismiss) private var dismiss

    let escapada: Escapada
    private let esNuevo: Bool

    @State private var tren: TrenViaje

    private let operadoras = ["Renfe", "Iryo", "Ouigo", "Otra"]

    init(escapada: Escapada, existente: TrenViaje?) {
        self.escapada = escapada
        self.esNuevo = (existente == nil)
        if let existente = existente {
            _tren = State(initialValue: existente)
        } else {
            var nuevo = TrenViaje()
            nuevo.escapadaId = escapada.id
            nuevo.fechaHoraSalida = escapada.fechaInicio.conHora(10)
            nuevo.fechaHoraLlegada = nuevo.fechaHoraSalida.addingTimeInterval(9000)
            nuevo.urlReserva = urlOperadoraTren("Renfe")
            _tren = State(initialValue: nuevo)
        }
    }

    private var puedeGuardar: Bool {
        !tren.estacionOrigen.recortado.isEmpty && !tren.estacionDestino.recortado.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Billete de tren") {
                    Picker("Trayecto", selection: $tren.trayecto) {
                        Text("Ida").tag("Ida")
                        Text("Vuelta").tag("Vuelta")
                    }
                    Picker("Operadora", selection: $tren.operadora) {
                        ForEach(operadoras, id: \.self) { op in
                            Text(op).tag(op)
                        }
                    }
                    TextField("Estación de origen (ej: Madrid Atocha)", text: $tren.estacionOrigen)
                    TextField("Estación de destino (ej: Valencia Joaquín Sorolla)", text: $tren.estacionDestino)
                    TextField("Localizador", text: $tren.localizador)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section("Horarios") {
                    DatePicker("Salida", selection: $tren.fechaHoraSalida)
                    DatePicker("Llegada", selection: $tren.fechaHoraLlegada)
                }

                Section {
                    TextField("URL del billete o de la web de la operadora", text: $tren.urlReserva)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Enlace")
                } footer: {
                    Text("Webs oficiales: renfe.com · iryo.eu · ouigo.com")
                }
            }
            .navigationTitle(esNuevo ? "Añadir tren" : "Editar tren")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: tren.trayecto) { _, nuevo in
                guard esNuevo else { return }
                let base = (nuevo == "Vuelta") ? escapada.fechaFin : escapada.fechaInicio
                tren.fechaHoraSalida = base.combinando(horaDe: tren.fechaHoraSalida)
            }
            .onChange(of: tren.fechaHoraSalida) { anterior, nueva in
                let duracion = tren.fechaHoraLlegada.timeIntervalSince(anterior)
                tren.fechaHoraLlegada = nueva.addingTimeInterval(duracion > 0 ? duracion : 9000)
            }
            .onChange(of: tren.operadora) { _, nueva in
                let conocidas = ["Renfe", "Iryo", "Ouigo"].map { urlOperadoraTren($0) }
                if tren.urlReserva.recortado.isEmpty || conocidas.contains(tren.urlReserva) {
                    tren.urlReserva = urlOperadoraTren(nueva)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(!puedeGuardar)
                }
            }
        }
    }

    private func guardar() {
        var t = tren
        t.escapadaId = escapada.id
        t.estacionOrigen = t.estacionOrigen.recortado
        t.estacionDestino = t.estacionDestino.recortado
        t.localizador = t.localizador.recortado.uppercased()
        t.urlReserva = t.urlReserva.recortado
        almacen.guardar(t, en: .trenes)
        dismiss()
    }
}

// MARK: - Alojamiento

struct FormularioAlojamiento: View {
    @EnvironmentObject var almacen: Almacen
    @Environment(\.dismiss) private var dismiss

    let escapada: Escapada
    private let esNuevo: Bool

    @State private var alojamiento: Alojamiento

    init(escapada: Escapada, existente: Alojamiento?) {
        self.escapada = escapada
        self.esNuevo = (existente == nil)
        if let existente = existente {
            _alojamiento = State(initialValue: existente)
        } else {
            var nuevo = Alojamiento()
            nuevo.escapadaId = escapada.id
            nuevo.entrada = escapada.fechaInicio.conHora(15)
            nuevo.salida = escapada.fechaFin.conHora(11)
            _alojamiento = State(initialValue: nuevo)
        }
    }

    private var puedeGuardar: Bool {
        !alojamiento.nombre.recortado.isEmpty || !alojamiento.direccion.recortado.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos del alojamiento") {
                    TextField("Nombre del hotel o apartamento", text: $alojamiento.nombre)
                    TextField("Dirección exacta o zona", text: $alojamiento.direccion)
                }

                Section("Fechas y horas") {
                    DatePicker("Entrada (check-in)", selection: $alojamiento.entrada)
                    DatePicker("Salida (check-out)", selection: $alojamiento.salida)
                }

                Section("Reserva") {
                    TextField("Código / localizador de la reserva", text: $alojamiento.codigoReserva)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    TextField("Enlace de la reserva (Booking, Airbnb…)", text: $alojamiento.urlReserva)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(esNuevo ? "Nuevo alojamiento" : "Editar alojamiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(!puedeGuardar)
                }
            }
        }
    }

    private func guardar() {
        var a = alojamiento
        a.escapadaId = escapada.id
        a.nombre = a.nombre.recortado
        a.direccion = a.direccion.recortado
        a.codigoReserva = a.codigoReserva.recortado.uppercased()
        a.urlReserva = a.urlReserva.recortado
        almacen.guardar(a, en: .alojamientos)
        dismiss()
    }
}
