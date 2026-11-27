import Foundation

// ============================================================================
// TASA OFICIAL DEL DÍA DEL GASTO (api.frankfurter.app: datos del Banco Central
// Europeo, gratis y sin clave). Para un gasto de otro día se usa la tasa de ese
// día y no la de hoy. Los fines de semana el BCE no publica: vale la del último
// día hábil. Monedas que el BCE no publica (dírham, libra egipcia…): se sigue
// usando la tasa de siempre.
// ============================================================================

struct TasaDelDia: Codable {
    let tasa: Double                        // 1 unidad de la divisa = X euros
    let fecha: String                       // día de la tasa del BCE ("2026-11-20")

    var fechaLegible: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: fecha) else { return fecha }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}

@MainActor
final class ServicioTasasDelDia {
    static let compartido = ServicioTasasDelDia()

    private var cache: [String: TasaDelDia] = [:]
    private let claveCache = "escapadas_tasas_bce_v1"

    private static let formatoDia: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        if let datos = UserDefaults.standard.data(forKey: claveCache),
           let guardadas = try? JSONDecoder().decode([String: TasaDelDia].self, from: datos) {
            cache = guardadas
        }
    }

    /// Tasa del BCE de `divisa` el día `dia`. nil si no la hay (moneda no incluida, sin conexión…).
    func tasa(de divisa: String, dia: Date) async -> TasaDelDia? {
        let codigo = divisa.uppercased()
        guard codigo != "EUR", codigo.count == 3, codigo.allSatisfy({ $0.isLetter }) else { return nil }
        let diaTexto = Self.formatoDia.string(from: dia)
        let clave = "\(codigo)-\(diaTexto)"
        if let t = cache[clave] { return t }

        guard let url = URL(string: "https://api.frankfurter.app/\(diaTexto)?from=\(codigo)&to=EUR") else { return nil }
        var peticion = URLRequest(url: url)
        peticion.timeoutInterval = 10
        guard let resultado = try? await URLSession.shared.data(for: peticion),
              (resultado.1 as? HTTPURLResponse)?.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: resultado.0)) as? [String: Any],
              let tasas = json["rates"] as? [String: Any],
              let euros = BuscadorVuelos.numeroJSON(tasas["EUR"]), euros > 0 else { return nil }

        let t = TasaDelDia(tasa: euros, fecha: (json["date"] as? String) ?? diaTexto)
        cache[clave] = t
        if let datos = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(datos, forKey: claveCache)
        }
        return t
    }
}
