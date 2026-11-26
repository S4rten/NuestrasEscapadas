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
//   (cada elemento es su propio documento y lleva "escapadaId")
// ============================================================================

enum Coleccion: String, CaseIterable {
    case escapadas, vuelos, trenes, alojamientos, gastos, checklist, actividades, ideas
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

    enum CodingKeys: String, CodingKey {
        case id, titulo, destino, latitud, longitud, divisaDestino, fechaInicio, fechaFin, icono
        case tieneVuelos, tieneTrenes, esSorpresa, pistaSorpresa, diasRevelarAntes, creadaPorId
        case momentoFavorito, recuerdo, valoracion, creadaEn
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

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, trayecto, origen, destino, fechaHoraSalida, fechaHoraLlegada
        case aerolinea, numeroVuelo, localizador, terminalPuerta, urlReserva
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

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, nombre, direccion, entrada, salida, codigoReserva, urlReserva
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

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, concepto, importe, importeOriginal, codigoDivisa, tasaAEuros
        case pagadoPorId, categoria, fecha
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

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, dia, nombreSitio, urlSitio, hora, completada, creadaEn
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
    }
}

struct Idea: Identifiable, Codable {
    var id: String = nuevoId()
    var escapadaId: String = ""
    var texto: String = ""
    var autorId: String = ""
    var creadaEn: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, escapadaId, texto, autorId, creadaEn
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
    }
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
}

struct ResumenGastos {
    let total: Double
    let pagadoPorMi: Double

    init(gastos: [Gasto], miId: String) {
        total = gastos.reduce(0) { $0 + $1.importe }
        pagadoPorMi = gastos.filter { $0.pagadoPorId == miId }.reduce(0) { $0 + $1.importe }
    }

    var pagadoPorPareja: Double { total - pagadoPorMi }

    /// Positivo: tu pareja te debe esa cantidad. Negativo: se la debes tú.
    var saldo: Double { pagadoPorMi - total / 2 }
}
