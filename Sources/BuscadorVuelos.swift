import Foundation

// ============================================================================
// SUGERENCIA DE RUTA A PARTIR DEL Nº DE VUELO (opcional, orientativa)
// Consulta api.adsbdb.com. Si no encuentra el vuelo, el formulario sigue siendo manual.
// ============================================================================

struct RutaVuelo {
    var aerolinea: String
    var origen: String
    var destino: String
    var urlGestion: String
    var ciudadOrigen: String = ""
    var ciudadDestino: String = ""
    var minutosAprox: Int? = nil            // estimado por la distancia (no es el horario real)
}

enum BuscadorVuelos {
    private struct Aerolinea {
        let iata: String
        let icao: String
        let nombre: String
        let url: String
    }

    private static let aerolineas: [Aerolinea] = [
        Aerolinea(iata: "IB", icao: "IBE", nombre: "Iberia", url: "https://www.iberia.com/es/gestion-reservas/"),
        Aerolinea(iata: "I2", icao: "IBS", nombre: "Iberia Express", url: "https://www.iberiaexpress.com"),
        Aerolinea(iata: "VY", icao: "VLG", nombre: "Vueling", url: "https://www.vueling.com/es/servicios-vueling/gestiona-tu-reserva"),
        Aerolinea(iata: "FR", icao: "RYR", nombre: "Ryanair", url: "https://www.ryanair.com/es/es/mybookings"),
        Aerolinea(iata: "UX", icao: "AEA", nombre: "Air Europa", url: "https://www.aireuropa.com"),
        Aerolinea(iata: "U2", icao: "EZY", nombre: "easyJet", url: "https://www.easyjet.com/es"),
        Aerolinea(iata: "V7", icao: "VOE", nombre: "Volotea", url: "https://www.volotea.com"),
        Aerolinea(iata: "LH", icao: "DLH", nombre: "Lufthansa", url: "https://www.lufthansa.com"),
        Aerolinea(iata: "AF", icao: "AFR", nombre: "Air France", url: "https://wwws.airfrance.es"),
        Aerolinea(iata: "BA", icao: "BAW", nombre: "British Airways", url: "https://www.britishairways.com"),
        Aerolinea(iata: "KL", icao: "KLM", nombre: "KLM", url: "https://www.klm.es"),
        Aerolinea(iata: "TP", icao: "TAP", nombre: "TAP Air Portugal", url: "https://www.flytap.com"),
        Aerolinea(iata: "AZ", icao: "ITY", nombre: "ITA Airways", url: "https://www.ita-airways.com"),
        Aerolinea(iata: "W6", icao: "WZZ", nombre: "Wizz Air", url: "https://wizzair.com"),
        Aerolinea(iata: "DY", icao: "NOZ", nombre: "Norwegian", url: "https://www.norwegian.com"),
        Aerolinea(iata: "EW", icao: "EWG", nombre: "Eurowings", url: "https://www.eurowings.com"),
        Aerolinea(iata: "LX", icao: "SWR", nombre: "Swiss", url: "https://www.swiss.com"),
        Aerolinea(iata: "OS", icao: "AUA", nombre: "Austrian", url: "https://www.austrian.com"),
        Aerolinea(iata: "SN", icao: "BEL", nombre: "Brussels Airlines", url: "https://www.brusselsairlines.com"),
        Aerolinea(iata: "SK", icao: "SAS", nombre: "SAS", url: "https://www.flysas.com"),
        Aerolinea(iata: "TK", icao: "THY", nombre: "Turkish Airlines", url: "https://www.turkishairlines.com"),
        Aerolinea(iata: "EI", icao: "EIN", nombre: "Aer Lingus", url: "https://www.aerlingus.com"),
        Aerolinea(iata: "HV", icao: "TRA", nombre: "Transavia", url: "https://www.transavia.com")
    ]

    static func buscar(numeroVuelo: String) async -> RutaVuelo? {
        let codigo = numeroVuelo
            .recortado
            .uppercased()
            .replacingOccurrences(of: " ", with: "")
        guard codigo.count >= 3 else { return nil }

        let aerolinea = aerolineaPorCodigo(codigo)
        let indicativo = indicativoICAO(codigo, aerolinea)
        guard let url = URL(string: "https://api.adsbdb.com/v0/callsign/\(indicativo)") else { return nil }

        var peticion = URLRequest(url: url)
        peticion.timeoutInterval = 8

        do {
            let (datos, respuesta) = try await URLSession.shared.data(for: peticion)
            guard let http = respuesta as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: datos) as? [String: Any],
                  let resp = json["response"] as? [String: Any],
                  let ruta = resp["flightroute"] as? [String: Any],
                  let origen = (ruta["origin"] as? [String: Any])?["iata_code"] as? String,
                  let destino = (ruta["destination"] as? [String: Any])?["iata_code"] as? String,
                  !origen.isEmpty, !destino.isEmpty
            else { return nil }

            let nombreApi = (ruta["airline"] as? [String: Any])?["name"] as? String
            let datosOrigen = (ruta["origin"] as? [String: Any]) ?? [:]
            let datosDestino = (ruta["destination"] as? [String: Any]) ?? [:]
            var minutos: Int? = nil
            if let la1 = numeroJSON(datosOrigen["latitude"]), let lo1 = numeroJSON(datosOrigen["longitude"]),
               let la2 = numeroJSON(datosDestino["latitude"]), let lo2 = numeroJSON(datosDestino["longitude"]) {
                minutos = minutosEstimados(lat1: la1, lon1: lo1, lat2: la2, lon2: lo2)
            }
            return RutaVuelo(
                aerolinea: aerolinea?.nombre ?? nombreApi ?? "",
                origen: origen.uppercased(),
                destino: destino.uppercased(),
                urlGestion: aerolinea?.url ?? "",
                ciudadOrigen: ((datosOrigen["municipality"] as? String) ?? "").recortado,
                ciudadDestino: ((datosDestino["municipality"] as? String) ?? "").recortado,
                minutosAprox: minutos
            )
        } catch {
            return nil
        }
    }

    private static func aerolineaPorCodigo(_ codigo: String) -> Aerolinea? {
        let prefijo3 = String(codigo.prefix(3))
        let prefijo2 = String(codigo.prefix(2))
        if let a = aerolineas.first(where: { $0.icao == prefijo3 }),
           codigo.dropFirst(3).allSatisfy({ $0.isNumber }) {
            return a
        }
        return aerolineas.first(where: { $0.iata == prefijo2 })
    }

    /// La API espera el indicativo ICAO (IBE3140), no el número IATA (IB3140).
    private static func indicativoICAO(_ codigo: String, _ aerolinea: Aerolinea?) -> String {
        guard let a = aerolinea else { return codigo }
        if codigo.hasPrefix(a.icao) { return codigo }
        if codigo.hasPrefix(a.iata) { return a.icao + codigo.dropFirst(2) }
        return codigo
    }
}

/// "2 h 35 min", "55 min"…
func textoDuracion(_ minutos: Int) -> String {
    let h = minutos / 60
    let m = minutos % 60
    if h == 0 { return "\(m) min" }
    if m == 0 { return "\(h) h" }
    return "\(h) h \(m) min"
}

// ============================================================================
// WEB DE "MI RESERVA" DE CADA AEROLÍNEA (para buscar con localizador y apellido)
// ============================================================================

struct WebAerolinea: Identifiable, Hashable {
    let nombre: String
    let iata: String
    let url: String
    var id: String { iata }
}

extension BuscadorVuelos {
    /// Todas las aerolíneas conocidas, por orden alfabético.
    static var webs: [WebAerolinea] {
        aerolineas
            .map { WebAerolinea(nombre: $0.nombre, iata: $0.iata, url: $0.url) }
            .sorted { $0.nombre.lowercased() < $1.nombre.lowercased() }
    }

    /// La aerolínea del vuelo: por el nº de vuelo (IB3140) o por el nombre escrito.
    static func web(paraNumero numero: String, aerolinea nombre: String) -> WebAerolinea? {
        let codigo = numero.recortado.uppercased().replacingOccurrences(of: " ", with: "")
        if codigo.count >= 3, let a = aerolineaPorCodigo(codigo) {
            return WebAerolinea(nombre: a.nombre, iata: a.iata, url: a.url)
        }
        let escrito = nombre.recortado.lowercased()
        guard !escrito.isEmpty else { return nil }
        let contenidas = aerolineas.filter { escrito.contains($0.nombre.lowercased()) }
        if let a = contenidas.max(by: { $0.nombre.count < $1.nombre.count }) {
            return WebAerolinea(nombre: a.nombre, iata: a.iata, url: a.url)
        }
        if let a = aerolineas.first(where: { $0.nombre.lowercased().contains(escrito) }) {
            return WebAerolinea(nombre: a.nombre, iata: a.iata, url: a.url)
        }
        return nil
    }

    // MARK: Duración aproximada (sin horario real)

    static func numeroJSON(_ valor: Any?) -> Double? {
        if let d = valor as? Double { return d }
        if let n = valor as? NSNumber { return n.doubleValue }
        if let s = valor as? String { return Double(s) }
        return nil
    }

    /// Minutos aproximados de vuelo según la distancia (crucero + despegue y aterrizaje).
    static func minutosEstimados(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Int? {
        let radio = 6371.0
        let rad = Double.pi / 180
        let s1 = sin((lat2 - lat1) * rad / 2)
        let s2 = sin((lon2 - lon1) * rad / 2)
        let cosenos = cos(lat1 * rad) * cos(lat2 * rad)
        let a = s1 * s1 + cosenos * s2 * s2
        let km = 2 * radio * atan2(sqrt(a), sqrt(1 - a))
        guard km > 30 else { return nil }
        let minutos = km / 820 * 60 + 30
        return Int((minutos / 5).rounded()) * 5
    }
}

// ============================================================================
// HORARIO REAL DEL VUELO (AeroDataBox, con una clave gratuita de RapidAPI)
// Con el nº de vuelo y el día trae: aeropuertos, ciudades, hora de salida y de
// llegada (la hora local de cada aeropuerto, como sale en el billete) y la
// duración real. La clave se guarda en vuestro espacio y la usan los dos iPhones.
// ============================================================================

struct HorarioVuelo: Identifiable {
    let id = UUID()
    var numero: String = ""
    var aerolinea: String = ""
    var origen: String = ""
    var destino: String = ""
    var ciudadOrigen: String = ""
    var ciudadDestino: String = ""
    var salida: Date? = nil                 // hora local del aeropuerto de salida
    var llegada: Date? = nil                // hora local del aeropuerto de llegada
    var minutos: Int? = nil                 // duración real del vuelo
    var terminal: String = ""

    var resumen: String {
        var texto = "\(origen) → \(destino)"
        if let s = salida {
            texto += " · sale a las " + s.formatted(date: .omitted, time: .shortened)
        }
        return texto
    }
}

enum ResultadoHorario {
    case encontrados([HorarioVuelo])
    case sinVuelo
    case claveNoValida
    case limiteAgotado
    case fallo(String)
}

extension BuscadorVuelos {
    static let webClaveGratis = "https://rapidapi.com/aedbx-aedbx/api/aerodatabox/pricing"

    static func buscarHorario(numeroVuelo: String, fecha: Date, clave: String) async -> ResultadoHorario {
        let codigo = numeroVuelo.uppercased().filter { $0.isLetter || $0.isNumber }
        let claveLimpia = clave.recortado
        guard codigo.count >= 3, !claveLimpia.isEmpty else { return .sinVuelo }

        let formato = DateFormatter()
        formato.locale = Locale(identifier: "en_US_POSIX")
        formato.calendar = Calendar(identifier: .gregorian)
        formato.timeZone = TimeZone.current
        formato.dateFormat = "yyyy-MM-dd"
        let dia = formato.string(from: fecha)

        var componentes = URLComponents()
        componentes.scheme = "https"
        componentes.host = "aerodatabox.p.rapidapi.com"
        componentes.path = "/flights/number/\(codigo)/\(dia)"
        componentes.queryItems = [
            URLQueryItem(name: "withAircraftImage", value: "false"),
            URLQueryItem(name: "withLocation", value: "false"),
            URLQueryItem(name: "dateLocalRole", value: "Departure")
        ]
        guard let url = componentes.url else { return .sinVuelo }

        var peticion = URLRequest(url: url)
        peticion.timeoutInterval = 15
        peticion.setValue(claveLimpia, forHTTPHeaderField: "X-RapidAPI-Key")
        peticion.setValue("aerodatabox.p.rapidapi.com", forHTTPHeaderField: "X-RapidAPI-Host")

        do {
            let (datos, respuesta) = try await URLSession.shared.data(for: peticion)
            let estado = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
            switch estado {
            case 200:
                break
            case 204, 404:
                return .sinVuelo
            case 401, 403:
                return .claveNoValida
            case 429:
                return .limiteAgotado
            default:
                return .fallo("El servicio de horarios ha fallado (error \(estado)).")
            }
            guard let lista = (try? JSONSerialization.jsonObject(with: datos)) as? [[String: Any]] else {
                return .sinVuelo
            }
            let horarios = lista.compactMap { horario(desde: $0) }
            return horarios.isEmpty ? .sinVuelo : .encontrados(horarios)
        } catch {
            return .fallo("No se pudo conectar con el servicio de horarios.")
        }
    }

    private static func horario(desde vuelo: [String: Any]) -> HorarioVuelo? {
        let salida = (vuelo["departure"] as? [String: Any]) ?? [:]
        let llegada = (vuelo["arrival"] as? [String: Any]) ?? [:]
        let aeropuertoSalida = (salida["airport"] as? [String: Any]) ?? [:]
        let aeropuertoLlegada = (llegada["airport"] as? [String: Any]) ?? [:]

        var h = HorarioVuelo()
        h.origen = codigoAeropuerto(aeropuertoSalida)
        h.destino = codigoAeropuerto(aeropuertoLlegada)
        guard !h.origen.isEmpty, !h.destino.isEmpty else { return nil }
        h.ciudadOrigen = ciudad(aeropuertoSalida)
        h.ciudadDestino = ciudad(aeropuertoLlegada)
        h.numero = ((vuelo["number"] as? String) ?? "").recortado
        h.aerolinea = (((vuelo["airline"] as? [String: Any])?["name"] as? String) ?? "").recortado
        h.terminal = ((salida["terminal"] as? String) ?? "").recortado

        let horasSalida = horasProgramadas(salida)
        let horasLlegada = horasProgramadas(llegada)
        if let local = horasSalida.local { h.salida = horaDePared(local) }
        if let local = horasLlegada.local { h.llegada = horaDePared(local) }

        let textoInicio = horasSalida.utc ?? horasSalida.local
        let textoFin = horasLlegada.utc ?? horasLlegada.local
        if let t1 = textoInicio, let t2 = textoFin, let inicio = instante(t1), let fin = instante(t2) {
            let m = Int((fin.timeIntervalSince(inicio) / 60).rounded())
            if m > 0 && m < 24 * 60 { h.minutos = m }
        }
        return h
    }

    private static func codigoAeropuerto(_ aeropuerto: [String: Any]) -> String {
        let iata = ((aeropuerto["iata"] as? String) ?? "").recortado
        if !iata.isEmpty { return iata.uppercased() }
        return ((aeropuerto["icao"] as? String) ?? "").recortado.uppercased()
    }

    private static func ciudad(_ aeropuerto: [String: Any]) -> String {
        for clave in ["municipalityName", "shortName", "name"] {
            if let t = aeropuerto[clave] as? String, !t.recortado.isEmpty { return t.recortado }
        }
        return ""
    }

    /// Las horas programadas vienen como {"scheduledTime": {"local", "utc"}} (o planas en versiones antiguas).
    private static func horasProgramadas(_ movimiento: [String: Any]) -> (local: String?, utc: String?) {
        if let t = movimiento["scheduledTime"] as? [String: Any] {
            return (t["local"] as? String, t["utc"] as? String)
        }
        return (movimiento["scheduledTimeLocal"] as? String, movimiento["scheduledTimeUtc"] as? String)
    }

    /// "2026-12-20 10:35+01:00" -> 20/12/2026 10:35 tal cual (la hora que pone el billete).
    private static func horaDePared(_ texto: String) -> Date? {
        let limpio = texto.replacingOccurrences(of: "T", with: " ")
        guard limpio.count >= 16 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: String(limpio.prefix(16)))
    }

    /// Instante exacto ("2026-12-20 09:35Z" o "…+01:00"), para calcular la duración real.
    private static func instante(_ texto: String) -> Date? {
        let limpio = texto.replacingOccurrences(of: "T", with: " ")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        for formato in ["yyyy-MM-dd HH:mmXXXXX", "yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss.SSSXXXXX", "yyyy-MM-dd HH:mmZ"] {
            f.dateFormat = formato
            if let d = f.date(from: limpio) { return d }
        }
        return nil
    }
}
