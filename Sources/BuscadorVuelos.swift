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
            return RutaVuelo(
                aerolinea: aerolinea?.nombre ?? nombreApi ?? "",
                origen: origen.uppercased(),
                destino: destino.uppercased(),
                urlGestion: aerolinea?.url ?? ""
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
