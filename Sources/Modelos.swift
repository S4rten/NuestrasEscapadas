import Foundation

// ============================================================================
// UTILIDADES COMUNES
// ============================================================================

func nuevoId() -> String { UUID().uuidString }

extension KeyedDecodingContainer {
    /// Lee un valor y, si falta o es de otro tipo, devuelve el valor por defecto.
    /// Así un documento antiguo o incompleto nunca hace que desaparezca un viaje.
    func valor<T: Decodable>(_ clave: Key, _ porDefecto: @autoclosure () -> T) -> T {
        if let v = try? decodeIfPresent(T.self, forKey: clave) { return v }
        return porDefecto()
    }
}

extension String {
    var recortado: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Date {
    var inicioDelDia: Date { Calendar.current.startOfDay(for: self) }

    func sumando(dias: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: dias, to: self) ?? self
    }

    func conHora(_ hora: Int, _ minuto: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hora, minute: minuto, second: 0, of: self) ?? self
    }

    /// Esta fecha (día) con la hora y los minutos de `otra`.
    func combinando(horaDe otra: Date) -> Date {
        let c = Calendar.current.dateComponents([.hour, .minute], from: otra)
        return conHora(c.hour ?? 0, c.minute ?? 0)
    }
}

extension Double {
    func formatoDivisa(_ codigo: String = "EUR") -> String {
        formatted(.currency(code: codigo))
    }
}

/// Convierte un texto en URL válida (añade https:// si falta). Devuelve nil si no es una URL.
func urlDesdeTexto(_ texto: String) -> URL? {
    var t = texto.recortado
    guard !t.isEmpty else { return nil }
    if !t.lowercased().hasPrefix("http") { t = "https://" + t }
    guard let url = URL(string: t), url.host != nil else { return nil }
    return url
}

func urlMapa(consulta: String) -> URL? {
    var comps = URLComponents(string: "https://maps.apple.com/")
    comps?.queryItems = [URLQueryItem(name: "q", value: consulta)]
    return comps?.url
}

// ============================================================================
// COLECCIONES DE FIRESTORE
//   parejas/{codigo}/miembros/{idDelIPhone}   -> nombre de cada persona
//   parejas/{codigo}/escapadas/{id}           -> cada viaje
//   parejas/{codigo}/vuelos|trenes|alojamientos|gastos|checklist|actividades|ideas/{id}
//   parejas/{codigo}/retos/{id}               -> retos de fotos (sin la imagen)
//   parejas/{codigo}/fotos/{idDelReto}        -> la foto de cada reto (se descarga al verla)
//   (cada elemento es su propio documento y lleva "escapadaId")
// ============================================================================

enum Coleccion: String, CaseIterable {
    case escapadas, vuelos, trenes, alojamientos, gastos, checklist, actividades, ideas
    case retos, fotos
    case pagos, fechasEspeciales
    case deseos
    case accesos, novedades, billetes, billetesDatos
    case opciones, huchas, aportaciones
}

struct Miembro: Identifiable, Hashable {
    let id: String
    let nombre: String
}

// ============================================================================
// VALORACIÓN
// ============================================================================

struct Valoracion: Codable, Hashable {
    var experienciaCiudad: Int = 0
    var museosCultura: Int = 0
    var gastronomia: Int = 0
    var alojamientoDescanso: Int = 0
    var momentosJuntos: Int = 0

    enum CodingKeys: String, CodingKey {
        case experienciaCiudad, museosCultura, gastronomia, alojamientoDescanso, momentosJuntos
    }

    var media: Double? {
        let notas = [experienciaCiudad, museosCultura, gastronomia, alojamientoDescanso, momentosJuntos]
            .filter { $0 > 0 }
        guard !notas.isEmpty else { return nil }
        return Double(notas.reduce(0, +)) / Double(notas.count)
    }
}

extension Valoracion {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        experienciaCiudad = c.valor(.experienciaCiudad, 0)
        museosCultura = c.valor(.museosCultura, 0)
        gastronomia = c.valor(.gastronomia, 0)
        alojamientoDescanso = c.valor(.alojamientoDescanso, 0)
        momentosJuntos = c.valor(.momentosJuntos, 0)
    }
}

// ============================================================================
// ESCAPADA (documento principal de cada viaje)
// ============================================================================

struct Escapada: Identifiable, Codable {
    var id: String = nuevoId()
    var titulo: String = ""
    var destino: String = ""
    var latitud: Double? = nil
    var longitud: Double? = nil
    var divisaDestino: String = "EUR"
    var fechaInicio: Date = Date()
    var fechaFin: Date = Date()
    var icono: String = "✈️"
    var tieneVuelos: Bool = false
    var tieneTrenes: Bool = false
    var esSorpresa: Bool = false
    var pistaSorpresa: String = ""
    var diasRevelarAntes: Int = 0
    var creadaPorId: String = ""
    var momentoFavorito: String = ""
    var recuerdo: String = ""
    var valoracion: Valoracion = Valoracion()
    var creadaEn: Date = Date()
    var presupuesto: Double = 0             // en euros; 0 = sin presupuesto
    var paisCodigo: String = ""             // ISO del país (ES, FR…); "" = sin saber

    enum CodingKeys: String, CodingKey {
        case id, titulo, destino, latitud, longitud, divisaDestino, fechaInicio, fechaFin, icono
        case tieneVuelos, tieneTrenes, esSorpresa, pistaSorpresa, diasRevelarAntes, creadaPorId
        case momentoFavorito, recuerdo, valoracion, creadaEn
        case presupuesto, paisCodigo
    }

    // MARK: Cálculos

    var yaVivida: Bool {
        Date() >= fechaFin.inicioDelDia.sumando(dias: 1)
    }

    var fechaRevelacion: Date {
        fechaInicio.inicioDelDia.sumando(dias: -max(0, diasRevelarAntes))
    }

    var sorpresaDesbloqueada: Bool {
        Date() >= fechaRevelacion
    }

    /// La sorpresa solo se oculta a la persona que NO la ha creado.
    func sorpresaOculta(para miId: String) -> Bool {
        esSorpresa && creadaPorId != miId && !sorpresaDesbloqueada
    }

    var totalDias: Int {
        let diff = Calendar.current.dateComponents([.day], from: fechaInicio.inicioDelDia, to: fechaFin.inicioDelDia).day ?? 0
        return max(1, diff + 1)
    }

    func fechaParaDia(_ dia: Int) -> Date {
        fechaInicio.inicioDelDia.sumando(dias: dia - 1)
    }

    var diasHastaInicio: Int {
        let d = Calendar.current.dateComponents([.day], from: Date().inicioDelDia, to: fechaInicio.inicioDelDia).day ?? 0
        return max(0, d)
    }

    var haEmpezado: Bool {
        Date() >= fechaInicio.inicioDelDia
    }
}

extension Escapada {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        titulo = c.valor(.titulo, "")
        destino = c.valor(.destino, "")
        latitud = try? c.decodeIfPresent(Double.self, forKey: .latitud)
        longitud = try? c.decodeIfPresent(Double.self, forKey: .longitud)
        divisaDestino = c.valor(.divisaDestino, "EUR")
        fechaInicio = c.valor(.fechaInicio, Date())
        fechaFin = c.valor(.fechaFin, Date())
        icono = c.valor(.icono, "✈️")
        tieneVuelos = c.valor(.tieneVuelos, false)
        tieneTrenes = c.valor(.tieneTrenes, false)
        esSorpresa = c.valor(.esSorpresa, false)
        pistaSorpresa = c.valor(.pistaSorpresa, "")
        diasRevelarAntes = c.valor(.diasRevelarAntes, 0)
        creadaPorId = c.valor(.creadaPorId, "")
        momentoFavorito = c.valor(.momentoFavorito, "")
        recuerdo = c.valor(.recuerdo, "")
        valoracion = c.valor(.valoracion, Valoracion())
        creadaEn = c.valor(.creadaEn, Date())
        presupuesto = c.valor(.presupuesto, 0.0)
        paisCodigo = c.valor(.paisCodigo, "")
    }
}

extension Escapada {
    var tienePresupuesto: Bool { presupuesto > 0 }

    /// El presupuesto solo se puede cambiar hasta el día anterior al viaje.
    var presupuestoEditable: Bool { !haEmpezado }

    /// Día del viaje (1, 2, 3…) al que pertenece una fecha, o nil si cae fuera del viaje.
    func diaDelViaje(para fecha: Date) -> Int? {
        let d = Calendar.current.dateComponents([.day], from: fechaInicio.inicioDelDia, to: fecha.inicioDelDia).day ?? -1
        let dia = d + 1
        return (1...totalDias).contains(dia) ? dia : nil
    }
}

// ============================================================================
// ELEMENTOS DE CADA ESCAPADA (cada uno es un documento independiente)
// ============================================================================

struct Vuelo: Identifiable, Codable {
    var id: String = nuevoId()
    var escapadaId: String = ""
    var trayecto: String = "Ida"            // Ida, Vuelta, Escala
    var origen: String = ""
    var destino: String = ""
    var fechaHoraSalida: Date = Date()
    var fechaHoraLlegada: Date = Date()
    var aerolinea: String = ""
    var numeroVuelo: String = ""
    var localizador: String = ""
    var terminalPuerta: String = ""
    var urlReserva: String = ""
    var ciudadOrigen: String = ""           // se rellena al buscar el vuelo (ej: "Madrid")
    var ciudadDestino: String = ""
    var duracionMinutos: Int = 0            // duración real del vuelo (0 = sin saber)

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, trayecto, origen, destino, fechaHoraSalida, fechaHoraLlegada
        case aerolinea, numeroVuelo, localizador, terminalPuerta, urlReserva
        case ciudadOrigen, ciudadDestino, duracionMinutos
    }
}

extension Vuelo {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        escapadaId = c.valor(.escapadaId, "")
        trayecto = c.valor(.trayecto, "Ida")
        origen = c.valor(.origen, "")
        destino = c.valor(.destino, "")
        fechaHoraSalida = c.valor(.fechaHoraSalida, Date())
        fechaHoraLlegada = c.valor(.fechaHoraLlegada, Date())
        aerolinea = c.valor(.aerolinea, "")
        numeroVuelo = c.valor(.numeroVuelo, "")
        localizador = c.valor(.localizador, "")
        terminalPuerta = c.valor(.terminalPuerta, "")
        urlReserva = c.valor(.urlReserva, "")
        ciudadOrigen = c.valor(.ciudadOrigen, "")
        ciudadDestino = c.valor(.ciudadDestino, "")
        duracionMinutos = c.valor(.duracionMinutos, 0)
    }
}

struct TrenViaje: Identifiable, Codable {
    var id: String = nuevoId()
    var escapadaId: String = ""
    var trayecto: String = "Ida"            // Ida, Vuelta
    var operadora: String = "Renfe"         // Renfe, Iryo, Ouigo, Otra
    var estacionOrigen: String = ""
    var estacionDestino: String = ""
    var fechaHoraSalida: Date = Date()
    var fechaHoraLlegada: Date = Date()
    var localizador: String = ""
    var urlReserva: String = ""

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, trayecto, operadora, estacionOrigen, estacionDestino
        case fechaHoraSalida, fechaHoraLlegada, localizador, urlReserva
    }
}

extension TrenViaje {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        escapadaId = c.valor(.escapadaId, "")
        trayecto = c.valor(.trayecto, "Ida")
        operadora = c.valor(.operadora, "Renfe")
        estacionOrigen = c.valor(.estacionOrigen, "")
        estacionDestino = c.valor(.estacionDestino, "")
        fechaHoraSalida = c.valor(.fechaHoraSalida, Date())
        fechaHoraLlegada = c.valor(.fechaHoraLlegada, Date())
        localizador = c.valor(.localizador, "")
        urlReserva = c.valor(.urlReserva, "")
    }
}

struct Alojamiento: Identifiable, Codable {
    var id: String = nuevoId()
    var escapadaId: String = ""
    var nombre: String = ""
    var direccion: String = ""
    var entrada: Date = Date()              // fecha y hora de check-in
    var salida: Date = Date()               // fecha y hora de check-out
    var codigoReserva: String = ""
    var urlReserva: String = ""
    var estrellas: Int = 0                  // valoración al volver (0 = sin valorar)

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, nombre, direccion, entrada, salida, codigoReserva, urlReserva
        case estrellas
    }
}

extension Alojamiento {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        escapadaId = c.valor(.escapadaId, "")
        nombre = c.valor(.nombre, "")
        direccion = c.valor(.direccion, "")
        entrada = c.valor(.entrada, Date())
        salida = c.valor(.salida, Date())
        codigoReserva = c.valor(.codigoReserva, "")
        urlReserva = c.valor(.urlReserva, "")
        estrellas = c.valor(.estrellas, 0)
    }
}

struct Gasto: Identifiable, Codable {
    var id: String = nuevoId()
    var escapadaId: String = ""
    var concepto: String = ""
    var importe: Double = 0                 // importe convertido a euros
    var importeOriginal: Double = 0         // importe en la divisa pagada
    var codigoDivisa: String = "EUR"
    var tasaAEuros: Double = 1              // 1 unidad de la divisa = X euros
    var pagadoPorId: String = ""            // ID del miembro que pagó
    var categoria: String = "Comida"
    var fecha: Date = Date()
    var porcentajePagador: Double = 50      // parte del gasto que corresponde a quien pagó (0–100)

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, concepto, importe, importeOriginal, codigoDivisa, tasaAEuros
        case pagadoPorId, categoria, fecha
        case porcentajePagador
    }

    /// Parte del gasto (en euros) que le corresponde a una persona.
    func parte(de miembroId: String) -> Double {
        let pct = min(max(porcentajePagador, 0), 100) / 100
        return pagadoPorId == miembroId ? importe * pct : importe * (1 - pct)
    }
}

extension Gasto {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        escapadaId = c.valor(.escapadaId, "")
        concepto = c.valor(.concepto, "")
        importe = c.valor(.importe, 0.0)
        importeOriginal = c.valor(.importeOriginal, importe)
        codigoDivisa = c.valor(.codigoDivisa, "EUR")
        tasaAEuros = c.valor(.tasaAEuros, 1.0)
        pagadoPorId = c.valor(.pagadoPorId, "")
        categoria = c.valor(.categoria, "Otros")
        fecha = c.valor(.fecha, Date())
        porcentajePagador = c.valor(.porcentajePagador, 50.0)
    }
}

enum CategoriaGasto: String, CaseIterable {
    case comida = "Comida"
    case transporte = "Transporte"
    case alojamiento = "Alojamiento"
    case entradas = "Entradas"
    case otros = "Otros"

    var icono: String {
        switch self {
        case .comida: return "🍽️"
        case .transporte: return "🚆"
        case .alojamiento: return "🛏️"
        case .entradas: return "🎟️"
        case .otros: return "🛍️"
        }
    }

    static func icono(para texto: String) -> String {
        (CategoriaGasto(rawValue: texto) ?? .otros).icono
    }
}

struct ItemChecklist: Identifiable, Codable {
    var id: String = nuevoId()
    var escapadaId: String = ""
    var texto: String = ""
    var completado: Bool = false
    var asignadoAId: String = ""            // "" = ambos; si no, ID del miembro
    var creadoEn: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, texto, completado, asignadoAId, creadoEn
    }
}

extension ItemChecklist {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        escapadaId = c.valor(.escapadaId, "")
        texto = c.valor(.texto, "")
        completado = c.valor(.completado, false)
        asignadoAId = c.valor(.asignadoAId, "")
        creadoEn = c.valor(.creadoEn, Date())
    }
}

struct Actividad: Identifiable, Codable {
    var id: String = nuevoId()
    var escapadaId: String = ""
    var dia: Int = 1
    var nombreSitio: String = ""
    var urlSitio: String = ""
    var hora: Date? = nil
    var completada: Bool = false
    var creadaEn: Date = Date()
    var todoElDia: Bool = false             // ocupa el día entero (parque de atracciones, excursión…)
    var latitud: Double? = nil              // posición en el mapa del día (se busca sola por el nombre)
    var longitud: Double? = nil
    var ubicacionBuscada: Bool = false      // true si ya se buscó (aunque no se encontrara)
    var ambiente: String = ""               // "interior", "exterior" o "" (se adivina por el nombre)
    var estrellas: Int = 0                  // valoración al volver (0 = sin valorar)
    var repetiriamos: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, dia, nombreSitio, urlSitio, hora, completada, creadaEn
        case todoElDia
        case latitud, longitud, ubicacionBuscada
        case ambiente, estrellas, repetiriamos
    }
}

extension Actividad {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        escapadaId = c.valor(.escapadaId, "")
        dia = c.valor(.dia, 1)
        nombreSitio = c.valor(.nombreSitio, "")
        urlSitio = c.valor(.urlSitio, "")
        hora = try? c.decodeIfPresent(Date.self, forKey: .hora)
        completada = c.valor(.completada, false)
        creadaEn = c.valor(.creadaEn, Date())
        todoElDia = c.valor(.todoElDia, false)
        latitud = try? c.decodeIfPresent(Double.self, forKey: .latitud)
        longitud = try? c.decodeIfPresent(Double.self, forKey: .longitud)
        ubicacionBuscada = c.valor(.ubicacionBuscada, false)
        ambiente = c.valor(.ambiente, "")
        estrellas = c.valor(.estrellas, 0)
        repetiriamos = c.valor(.repetiriamos, false)
    }
}

struct Idea: Identifiable, Codable {
    var id: String = nuevoId()
    var escapadaId: String = ""
    var texto: String = ""
    var autorId: String = ""
    var creadaEn: Date = Date()
    var votos: [String: Int] = [:]          // ID del miembro -> 1 o -1

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, texto, autorId, creadaEn
        case votos
    }
}

extension Idea {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        escapadaId = c.valor(.escapadaId, "")
        texto = c.valor(.texto, "")
        autorId = c.valor(.autorId, "")
        creadaEn = c.valor(.creadaEn, Date())
        votos = c.valor(.votos, [String: Int]())
    }
}

/// Puntuación de unos votos: suma de 👍 (+1) y 👎 (-1).
func puntuacion(_ votos: [String: Int]) -> Int {
    votos.values.reduce(0, +)
}

// ============================================================================
// WISHLIST: sitios y experiencias que queréis hacer algún día
// ============================================================================

enum CategoriaDeseo: String, CaseIterable, Identifiable, Codable {
    case destino, experiencia, comida, aventura, relax, otro

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .destino: return "🌍"
        case .experiencia: return "✨"
        case .comida: return "🍽️"
        case .aventura: return "🧗"
        case .relax: return "🧖"
        case .otro: return "💫"
        }
    }

    var nombre: String {
        switch self {
        case .destino: return "Destino"
        case .experiencia: return "Experiencia"
        case .comida: return "Comida"
        case .aventura: return "Aventura"
        case .relax: return "Relax"
        case .otro: return "Otro"
        }
    }
}

struct Deseo: Identifiable, Codable {
    var id: String = nuevoId()
    var titulo: String = ""
    var lugar: String = ""                  // opcional: dónde (para convertirlo en escapada)
    var notas: String = ""
    var categoria: CategoriaDeseo = .destino
    var votos: [String: Int] = [:]          // ID del miembro -> 1 (¡muchas ganas!) o -1 (no tanto)
    var cumplido: Bool = false
    var cumplidoEn: Date? = nil
    var creadoPorId: String = ""
    var creadoEn: Date = Date()
    // Ubicación del lugar (se busca sola) para relacionarlo con escapadas por país o cercanía.
    var latitud: Double? = nil
    var longitud: Double? = nil
    var paisCodigo: String = ""
    var esPais: Bool = false                // el lugar es un país entero (ej: "Italia")
    var ubicacionBuscada: String = ""       // texto que se buscó la última vez ("" = nunca)

    enum CodingKeys: String, CodingKey {
        case id, titulo, lugar, notas, categoria, votos, cumplido, cumplidoEn, creadoPorId, creadoEn
        case latitud, longitud, paisCodigo, esPais, ubicacionBuscada
    }

    /// Texto que identifica el sitio: el lugar o, si es un destino sin lugar, el propio título.
    var textoUbicacion: String {
        let base = lugar.recortado.isEmpty && categoria == .destino ? titulo : lugar
        return base.recortado
    }
}

extension Deseo {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        titulo = c.valor(.titulo, "")
        lugar = c.valor(.lugar, "")
        notas = c.valor(.notas, "")
        categoria = CategoriaDeseo(rawValue: c.valor(.categoria, "destino")) ?? .otro
        votos = c.valor(.votos, [String: Int]())
        cumplido = c.valor(.cumplido, false)
        cumplidoEn = try? c.decodeIfPresent(Date.self, forKey: .cumplidoEn)
        creadoPorId = c.valor(.creadoPorId, "")
        creadoEn = c.valor(.creadoEn, Date())
        latitud = try? c.decodeIfPresent(Double.self, forKey: .latitud)
        longitud = try? c.decodeIfPresent(Double.self, forKey: .longitud)
        paisCodigo = c.valor(.paisCodigo, "")
        esPais = c.valor(.esPais, false)
        ubicacionBuscada = c.valor(.ubicacionBuscada, "")
    }
}

// ============================================================================
// ACCESOS: iPhones con permiso para entrar en el espacio (uno por usuario anónimo)
// ============================================================================

struct Acceso: Identifiable, Codable {
    var id: String = ""                     // UID anónimo de Firebase de ese iPhone
    var miId: String = ""                   // ID de la persona dentro de la app
    var nombre: String = ""
    var creadoEn: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, miId, nombre, creadoEn
    }
}

extension Acceso {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, "")
        miId = c.valor(.miId, "")
        nombre = c.valor(.nombre, "")
        creadoEn = c.valor(.creadoEn, Date())
    }
}

// ============================================================================
// BILLETES: fotos de tarjetas de embarque, QR de entradas… de una reserva.
// La imagen va aparte, en "billetesDatos", con el mismo ID.
// ============================================================================

struct Billete: Identifiable, Codable {
    var id: String = nuevoId()
    var escapadaId: String = ""
    var reservaId: String = ""              // vuelo, tren o alojamiento
    var titulo: String = ""
    var creadoPorId: String = ""
    var creadoEn: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, reservaId, titulo, creadoPorId, creadoEn
    }
}

extension Billete {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        escapadaId = c.valor(.escapadaId, "")
        reservaId = c.valor(.reservaId, "")
        titulo = c.valor(.titulo, "")
        creadoPorId = c.valor(.creadoPorId, "")
        creadoEn = c.valor(.creadoEn, Date())
    }
}

// ============================================================================
// NOVEDADES: lo último que ha hecho cada uno (para "Actividad reciente")
// ============================================================================

struct Novedad: Identifiable, Codable {
    var id: String = nuevoId()
    var autorId: String = ""
    var icono: String = "✨"
    var texto: String = ""                  // ej: "añadió un gasto: Cena (45,00 €)"
    var escapadaId: String = ""             // "" si no es de una escapada (deseos, fechas…)
    var fecha: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, autorId, icono, texto, escapadaId, fecha
    }
}

extension Novedad {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        autorId = c.valor(.autorId, "")
        icono = c.valor(.icono, "✨")
        texto = c.valor(.texto, "")
        escapadaId = c.valor(.escapadaId, "")
        fecha = c.valor(.fecha, Date())
    }
}

// ============================================================================
// OPCIONES: candidatos antes de reservar (2-3 hoteles, vuelos…) para votar.
// ============================================================================

enum TipoOpcion: String, CaseIterable, Identifiable {
    case alojamiento, vuelo, tren, coche, actividad, otro

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .alojamiento: return "🛏️"
        case .vuelo: return "✈️"
        case .tren: return "🚂"
        case .coche: return "🚗"
        case .actividad: return "🎟️"
        case .otro: return "💫"
        }
    }

    var nombre: String {
        switch self {
        case .alojamiento: return "Alojamiento"
        case .vuelo: return "Vuelo"
        case .tren: return "Tren"
        case .coche: return "Coche de alquiler"
        case .actividad: return "Actividad o entrada"
        case .otro: return "Otro"
        }
    }

    /// Las que se pueden pasar a Reservas con un toque.
    var vaAReservas: Bool { self == .alojamiento || self == .vuelo || self == .tren }
}

struct Opcion: Identifiable, Codable {
    var id: String = nuevoId()
    var escapadaId: String = ""
    var tipo: String = TipoOpcion.alojamiento.rawValue
    var titulo: String = ""
    var precio: Double = 0                  // en euros; 0 = sin precio
    var enlace: String = ""
    var notas: String = ""
    var votos: [String: Int] = [:]          // ID del miembro -> 1 o -1
    var elegida: Bool = false
    var creadoPorId: String = ""
    var creadoEn: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, tipo, titulo, precio, enlace, notas, votos, elegida, creadoPorId, creadoEn
    }

    var tipoOpcion: TipoOpcion { TipoOpcion(rawValue: tipo) ?? .otro }
}

extension Opcion {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        escapadaId = c.valor(.escapadaId, "")
        tipo = c.valor(.tipo, TipoOpcion.otro.rawValue)
        titulo = c.valor(.titulo, "")
        precio = c.valor(.precio, 0.0)
        enlace = c.valor(.enlace, "")
        notas = c.valor(.notas, "")
        votos = c.valor(.votos, [String: Int]())
        elegida = c.valor(.elegida, false)
        creadoPorId = c.valor(.creadoPorId, "")
        creadoEn = c.valor(.creadoEn, Date())
    }
}

// ============================================================================
// HUCHA: ahorro común con objetivo ("Japón: 3.000 €") y aportaciones de cada uno.
// ============================================================================

struct Hucha: Identifiable, Codable {
    var id: String = nuevoId()
    var titulo: String = ""
    var emoji: String = "🐷"
    var objetivo: Double = 0                // en euros
    var fechaObjetivo: Date? = nil          // opcional: para cuándo lo queréis
    var creadaPorId: String = ""
    var creadaEn: Date = Date()
    var cerrada: Bool = false               // ya se usó (o se abandonó)

    enum CodingKeys: String, CodingKey {
        case id, titulo, emoji, objetivo, fechaObjetivo, creadaPorId, creadaEn, cerrada
    }
}

extension Hucha {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        titulo = c.valor(.titulo, "")
        emoji = c.valor(.emoji, "🐷")
        objetivo = c.valor(.objetivo, 0.0)
        fechaObjetivo = try? c.decodeIfPresent(Date.self, forKey: .fechaObjetivo)
        creadaPorId = c.valor(.creadaPorId, "")
        creadaEn = c.valor(.creadaEn, Date())
        cerrada = c.valor(.cerrada, false)
    }
}

struct Aportacion: Identifiable, Codable {
    var id: String = nuevoId()
    var huchaId: String = ""
    var autorId: String = ""
    var importe: Double = 0                 // en euros (negativo = se sacó dinero)
    var nota: String = ""
    var fecha: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, huchaId, autorId, importe, nota, fecha
    }
}

extension Aportacion {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        huchaId = c.valor(.huchaId, "")
        autorId = c.valor(.autorId, "")
        importe = c.valor(.importe, 0.0)
        nota = c.valor(.nota, "")
        fecha = c.valor(.fecha, Date())
    }
}

// ============================================================================
// PAGOS ENTRE VOSOTROS (para saldar cuentas; no cuentan como gasto del viaje)
// ============================================================================

struct PagoPareja: Identifiable, Codable {
    var id: String = nuevoId()
    var escapadaId: String = ""
    var deId: String = ""                   // quien paga la deuda
    var aId: String = ""                    // quien la recibe
    var importe: Double = 0                 // en euros
    var fecha: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, deId, aId, importe, fecha
    }
}

extension PagoPareja {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        escapadaId = c.valor(.escapadaId, "")
        deId = c.valor(.deId, "")
        aId = c.valor(.aId, "")
        importe = c.valor(.importe, 0.0)
        fecha = c.valor(.fecha, Date())
    }
}

// ============================================================================
// FECHAS ESPECIALES (aniversarios, cumpleaños…)
// ============================================================================

struct FechaEspecial: Identifiable, Codable {
    var id: String = nuevoId()
    var titulo: String = ""
    var emoji: String = "💍"
    var fecha: Date = Date()
    var anual: Bool = true                  // se repite cada año
    var creadaPorId: String = ""

    enum CodingKeys: String, CodingKey {
        case id, titulo, emoji, fecha, anual, creadaPorId
    }

    /// Próxima vez que toca (hoy incluido). nil si no es anual y ya pasó.
    func proximaOcurrencia(desde hoy: Date = Date()) -> Date? {
        let cal = Calendar.current
        let inicioHoy = hoy.inicioDelDia
        guard anual else {
            return fecha.inicioDelDia >= inicioHoy ? fecha.inicioDelDia : nil
        }
        let partes = cal.dateComponents([.month, .day], from: fecha)
        return cal.nextDate(after: inicioHoy.sumando(dias: -1),
                            matching: DateComponents(month: partes.month, day: partes.day),
                            matchingPolicy: .nextTimePreservingSmallerComponents)?.inicioDelDia
    }

    func diasHasta(desde hoy: Date = Date()) -> Int? {
        guard let proxima = proximaOcurrencia(desde: hoy) else { return nil }
        return Calendar.current.dateComponents([.day], from: hoy.inicioDelDia, to: proxima).day
    }

    /// Años que se cumplen en la próxima ocurrencia (solo si es anual y la fecha es pasada).
    func anosQueSeCumplen(desde hoy: Date = Date()) -> Int? {
        guard anual, let proxima = proximaOcurrencia(desde: hoy) else { return nil }
        let anos = Calendar.current.dateComponents([.year], from: fecha.inicioDelDia, to: proxima).year ?? 0
        return anos > 0 ? anos : nil
    }
}

extension FechaEspecial {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        titulo = c.valor(.titulo, "")
        emoji = c.valor(.emoji, "💍")
        fecha = c.valor(.fecha, Date())
        anual = c.valor(.anual, true)
        creadaPorId = c.valor(.creadaPorId, "")
    }
}

// ============================================================================
// RETOS DE FOTOS (la imagen va aparte, en la colección "fotos", con el mismo ID)
// ============================================================================

struct Reto: Identifiable, Codable {
    var id: String = nuevoId()
    var escapadaId: String = ""
    var texto: String = ""
    var creadoPorId: String = ""
    var creadoEn: Date = Date()
    var completado: Bool = false
    var completadoPorId: String = ""
    var fotoEn: Date? = nil                 // cuándo se subió la foto (sirve para refrescar la caché)

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, texto, creadoPorId, creadoEn, completado, completadoPorId, fotoEn
    }

    /// Clave única de la foto actual: cambia cada vez que se sube una foto nueva.
    var claveFoto: String {
        "\(id)-\(Int((fotoEn ?? creadoEn).timeIntervalSince1970))"
    }
}

extension Reto {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.valor(.id, nuevoId())
        escapadaId = c.valor(.escapadaId, "")
        texto = c.valor(.texto, "")
        creadoPorId = c.valor(.creadoPorId, "")
        creadoEn = c.valor(.creadoEn, Date())
        completado = c.valor(.completado, false)
        completadoPorId = c.valor(.completadoPorId, "")
        fotoEn = try? c.decodeIfPresent(Date.self, forKey: .fotoEn)
    }
}

enum RetosSugeridos {
    static let lista = [
        "🤳 Selfie con el monumento más famoso",
        "🍽️ Selfie probando la comida típica",
        "🌅 Foto del atardecer juntos",
        "🗿 Imitad una estatua",
        "🙋 Foto con alguien del lugar",
        "🦘 Selfie saltando a la vez",
        "☕️ El mejor café del viaje",
        "🪧 Un cartel con un nombre gracioso",
        "🌃 Foto nocturna de la ciudad",
        "💋 Beso en el sitio más bonito"
    ]
}

// ============================================================================
// APOYO PARA LA INTERFAZ
// ============================================================================

struct EventoLinea: Identifiable {
    let id: String
    let hora: Date?              // nil = actividad sin hora fija
    let titulo: String
    let subtitulo: String
    let icono: String
    let actividadId: String?     // si no es nil, es una actividad editable
    let completada: Bool
    let enlace: URL?
    var ruta: URL? = nil         // "Cómo llegar" en Apple Maps
    var todoElDia: Bool = false  // plan que ocupa el día entero
}

struct ResumenGastos {
    let total: Double
    let pagadoPorMi: Double
    let miParte: Double          // lo que me toca pagar según el reparto de cada gasto
    let pagosHechos: Double      // lo que yo he pagado a mi pareja para saldar
    let pagosRecibidos: Double   // lo que mi pareja me ha pagado para saldar

    init(gastos: [Gasto], miId: String, pagos: [PagoPareja] = []) {
        total = gastos.reduce(0) { $0 + $1.importe }
        pagadoPorMi = gastos.filter { $0.pagadoPorId == miId }.reduce(0) { $0 + $1.importe }
        miParte = gastos.reduce(0) { $0 + $1.parte(de: miId) }
        pagosHechos = pagos.filter { $0.deId == miId }.reduce(0) { $0 + $1.importe }
        pagosRecibidos = pagos.filter { $0.aId == miId }.reduce(0) { $0 + $1.importe }
    }

    var pagadoPorPareja: Double { total - pagadoPorMi }

    /// Positivo: tu pareja te debe esa cantidad. Negativo: se la debes tú.
    var saldo: Double { pagadoPorMi - miParte + pagosHechos - pagosRecibidos }
}
