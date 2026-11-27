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
    @State private var horariosEncontrados: [HorarioVuelo] = []   // si ese día hay varios tramos
    @State private var vuelosDeLaReserva: [String] = []           // leídos de la web de la aerolínea
    @State private var webAbierta: WebAerolinea? = nil
    @State private var horasDeBusqueda = false                    // las horas las acaba de poner la búsqueda

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

    private var textoPieBusqueda: String {
        if almacen.claveVuelos.recortado.isEmpty {
            return "Con el nº de vuelo se rellenan la ruta y las ciudades. Activando los horarios, también la hora de salida, la de llegada y la duración. Compruébalo siempre con tu billete."
        }
        let dia = vuelo.diaSalidaLocal
        return "Se busca el vuelo del día de la salida (\(dia)) y se rellenan la ruta, las ciudades, las horas y la duración. Compruébalo siempre con tu billete."
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
                    TextField("Asientos (ej: 14C y 14D)", text: $vuelo.asiento)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
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
                            Text(buscando ? "Buscando…" : "Buscar los datos del vuelo")
                        }
                    }
                    .disabled(buscando || vuelo.numeroVuelo.recortado.count < 3)

                    if !mensaje.isEmpty {
                        Text(mensaje)
                            .font(.caption)
                            .foregroundStyle(mensajeEsError ? Color.orange : Color.green)
                    }

                    ForEach(horariosEncontrados) { h in
                        Button {
                            aplicar(h)
                        } label: {
                            Label(h.resumen, systemImage: "airplane.departure")
                        }
                    }

                    if almacen.claveVuelos.recortado.isEmpty {
                        NavigationLink {
                            ClaveVuelosView()
                        } label: {
                            Label("Activar horarios automáticos (gratis)", systemImage: "clock.badge.checkmark")
                        }
                    }
                } footer: {
                    Text(textoPieBusqueda)
                }

                Section {
                    if let w = BuscadorVuelos.web(paraNumero: vuelo.numeroVuelo, aerolinea: vuelo.aerolinea) {
                        Button {
                            webAbierta = w
                        } label: {
                            Label("Abrir mi reserva en \(w.nombre)", systemImage: "person.text.rectangle")
                        }
                    }
                    Menu {
                        ForEach(BuscadorVuelos.webs) { w in
                            Button(w.nombre) { webAbierta = w }
                        }
                    } label: {
                        Label("Elegir la aerolínea…", systemImage: "list.bullet")
                    }
                    ForEach(vuelosDeLaReserva, id: \.self) { numero in
                        Button {
                            vuelo.numeroVuelo = numero
                            vuelosDeLaReserva = []
                            Task { await buscar() }
                        } label: {
                            Label("Usar el vuelo \(numero)", systemImage: "airplane")
                        }
                    }
                } header: {
                    Text("Con localizador y apellido")
                } footer: {
                    Text("Se abre la web de la aerolínea aquí dentro: escribe el localizador (se copia solo) y tu apellido. Cuando veas tus vuelos, la app lee los números de vuelo de la página y busca el resto. No se guarda nada de esa web.")
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
                    HStack {
                        TextField("Ciudad de origen", text: $vuelo.ciudadOrigen)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("Ciudad de destino", text: $vuelo.ciudadDestino)
                    }
                    // Cada hora en la hora local de su aeropuerto (como en el billete).
                    DatePicker("Salida", selection: $vuelo.fechaHoraSalida)
                        .environment(\.timeZone, vuelo.zonaDeSalida)
                    DatePicker("Llegada", selection: $vuelo.fechaHoraLlegada)
                        .environment(\.timeZone, vuelo.zonaDeLlegada)
                    if vuelo.tieneHoraLocalDistinta {
                        Text("Horas locales: salida en hora de \(vuelo.zonaDeSalida.ciudadLegible), llegada en hora de \(vuelo.zonaDeLlegada.ciudadLegible).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let minutos = vuelo.minutosDeVuelo {
                        HStack {
                            Text("Duración del vuelo")
                            Spacer()
                            Text(textoDuracion(minutos))
                                .foregroundStyle(.secondary)
                        }
                    }
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
                // Si las horas las acaba de poner la búsqueda, ya vienen bien las dos.
                if horasDeBusqueda {
                    horasDeBusqueda = false
                    return
                }
                // Mantiene la duración del vuelo al cambiar la hora de salida.
                let duracion = vuelo.fechaHoraLlegada.timeIntervalSince(anterior)
                vuelo.fechaHoraLlegada = nueva.addingTimeInterval(duracion > 0 ? duracion : 9000)
            }
            .sheet(item: $webAbierta) { w in
                if let url = URL(string: w.url) {
                    NavegadorReserva(url: url, nombreAerolinea: w.nombre, localizador: vuelo.localizador) { encontrados in
                        recibirVuelosLeidos(encontrados)
                    }
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

    private func buscar() async {
        buscando = true
        mensaje = ""
        horariosEncontrados = []
        let clave = almacen.claveVuelos.recortado
        var aviso = ""

        // 1) Con la clave: horario real de ese día.
        if !clave.isEmpty {
            let resultado = await BuscadorVuelos.buscarHorario(numeroVuelo: vuelo.numeroVuelo, fecha: vuelo.fechaHoraSalida, clave: clave, zona: vuelo.zonaDeSalida)
            switch resultado {
            case .encontrados(let lista):
                buscando = false
                if lista.count == 1, let unico = lista.first {
                    aplicar(unico)
                } else {
                    horariosEncontrados = lista
                    mensajeEsError = false
                    mensaje = "Ese vuelo hace \(lista.count) tramos ese día: toca el tuyo."
                }
                return
            case .sinVuelo:
                aviso = "No hay horario de ese vuelo el \(vuelo.diaSalidaLocal) (revisa el día de la salida). "
            case .claveNoValida:
                aviso = "La clave de horarios no funciona: revísala en Ajustes › Horarios de vuelos. "
            case .limiteAgotado:
                aviso = "Se han acabado las búsquedas de horarios gratis de este mes. "
            case .fallo(let texto):
                aviso = texto + " "
            }
        }

        // 2) Sin clave (o sin horario): al menos la ruta y las ciudades.
        let ruta = await BuscadorVuelos.buscar(numeroVuelo: vuelo.numeroVuelo)
        buscando = false
        if let ruta = ruta {
            vuelo.origen = ruta.origen
            vuelo.destino = ruta.destino
            if !ruta.ciudadOrigen.isEmpty { vuelo.ciudadOrigen = ruta.ciudadOrigen }
            if !ruta.ciudadDestino.isEmpty { vuelo.ciudadDestino = ruta.ciudadDestino }
            if vuelo.aerolinea.recortado.isEmpty && !ruta.aerolinea.isEmpty { vuelo.aerolinea = ruta.aerolinea }
            if vuelo.urlReserva.recortado.isEmpty && !ruta.urlGestion.isEmpty { vuelo.urlReserva = ruta.urlGestion }
            await ponerZonas(ruta)
            var texto = aviso + "Ruta: \(ciudadYCodigo(ruta.ciudadOrigen, ruta.origen)) → \(ciudadYCodigo(ruta.ciudadDestino, ruta.destino))"
            if let m = ruta.minutosAprox {
                texto += " · unas \(textoDuracion(m)) de vuelo"
            }
            texto += ". Compruébala con tu billete."
            mensajeEsError = !aviso.isEmpty
            mensaje = texto
        } else {
            mensajeEsError = true
            mensaje = aviso + "No se encontró ese vuelo. Escribe el origen y el destino a mano."
        }
    }

    /// Rellena el vuelo con el horario encontrado.
    private func aplicar(_ h: HorarioVuelo) {
        horariosEncontrados = []
        vuelo.origen = h.origen
        vuelo.destino = h.destino
        if !h.ciudadOrigen.isEmpty { vuelo.ciudadOrigen = h.ciudadOrigen }
        if !h.ciudadDestino.isEmpty { vuelo.ciudadDestino = h.ciudadDestino }
        if vuelo.aerolinea.recortado.isEmpty && !h.aerolinea.isEmpty { vuelo.aerolinea = h.aerolinea }
        if vuelo.terminalPuerta.recortado.isEmpty && !h.terminal.isEmpty { vuelo.terminalPuerta = "Terminal \(h.terminal)" }
        if let m = h.minutos { vuelo.duracionMinutos = m }
        if let exacta = h.salidaExacta, !h.zonaSalida.isEmpty, TimeZone(identifier: h.zonaSalida) != nil {
            // Instantes exactos + zona de cada aeropuerto: se ve la hora local aunque el iPhone esté en otra zona.
            if exacta != vuelo.fechaHoraSalida { horasDeBusqueda = true }
            vuelo.zonaSalida = h.zonaSalida
            vuelo.fechaHoraSalida = exacta
            if let llegada = h.llegadaExacta, !h.zonaLlegada.isEmpty, TimeZone(identifier: h.zonaLlegada) != nil {
                vuelo.zonaLlegada = h.zonaLlegada
                vuelo.fechaHoraLlegada = llegada
            } else {
                vuelo.zonaLlegada = h.zonaSalida
                vuelo.fechaHoraLlegada = exacta.addingTimeInterval(Double((h.minutos ?? 150) * 60))
            }
        } else if let salida = h.salida {
            // Sin zonas: la hora tal cual sale en el billete, en la zona del iPhone.
            if salida != vuelo.fechaHoraSalida { horasDeBusqueda = true }
            vuelo.zonaSalida = ""
            vuelo.zonaLlegada = ""
            vuelo.fechaHoraSalida = salida
            vuelo.fechaHoraLlegada = h.llegada ?? salida.addingTimeInterval(Double((h.minutos ?? 150) * 60))
        }
        if vuelo.urlReserva.recortado.isEmpty,
           let w = BuscadorVuelos.web(paraNumero: vuelo.numeroVuelo, aerolinea: vuelo.aerolinea) {
            vuelo.urlReserva = w.url
        }

        var partes = ["\(ciudadYCodigo(h.ciudadOrigen, h.origen)) → \(ciudadYCodigo(h.ciudadDestino, h.destino))"]
        if let s = h.salida {
            partes.append("sale a las " + s.formatted(date: .omitted, time: .shortened))
        }
        if let m = h.minutos {
            partes.append(textoDuracion(m) + " de vuelo")
        }
        mensajeEsError = false
        mensaje = "✅ " + partes.joined(separator: " · ") + ". Compruébalo con tu billete."
    }

    /// Números de vuelo leídos de la web de la aerolínea.
    private func recibirVuelosLeidos(_ numeros: [String]) {
        if numeros.count == 1, let unico = numeros.first {
            vuelo.numeroVuelo = unico
            vuelosDeLaReserva = []
            Task { await buscar() }
        } else {
            vuelosDeLaReserva = numeros
            mensajeEsError = false
            mensaje = "En tu reserva hay \(numeros.count) vuelos: elige abajo cuál es este."
        }
    }

    private func ciudadYCodigo(_ ciudad: String, _ codigo: String) -> String {
        ciudad.isEmpty ? codigo : "\(ciudad) (\(codigo))"
    }

    /// Sin horario real: averigua la zona horaria de cada aeropuerto por su posición y
    /// deja las horas escritas tal cual (las 18:00 siguen siendo las 18:00, ahora en hora local).
    private func ponerZonas(_ ruta: RutaVuelo) async {
        var zonaSalidaNueva: TimeZone? = nil
        var zonaLlegadaNueva: TimeZone? = nil
        if let lat = ruta.latOrigen, let lon = ruta.lonOrigen {
            zonaSalidaNueva = await ZonasDestino.compartido.averiguar(lat: lat, lon: lon)
        }
        if let lat = ruta.latDestino, let lon = ruta.lonDestino {
            zonaLlegadaNueva = await ZonasDestino.compartido.averiguar(lat: lat, lon: lon)
        }
        let salidaAntes = vuelo.fechaHoraSalida
        let llegadaAntes = vuelo.fechaHoraLlegada
        if let z = zonaSalidaNueva, z.identifier != vuelo.zonaSalida {
            let nueva = salidaAntes.mismaHoraDeReloj(de: vuelo.zonaDeSalida, a: z)
            if nueva != salidaAntes { horasDeBusqueda = true }
            vuelo.zonaSalida = z.identifier
            vuelo.fechaHoraSalida = nueva
        }
        if let z = zonaLlegadaNueva, z.identifier != vuelo.zonaLlegada {
            vuelo.fechaHoraLlegada = llegadaAntes.mismaHoraDeReloj(de: vuelo.zonaDeLlegada, a: z)
            vuelo.zonaLlegada = z.identifier
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
        v.ciudadOrigen = v.ciudadOrigen.recortado
        v.ciudadDestino = v.ciudadDestino.recortado
        v.asiento = v.asiento.recortado
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
