import Foundation

// ============================================================================
// DIVISAS: lista de monedas del sistema + tasas en vivo (se guardan para uso sin conexión)
// ============================================================================

struct DivisaInfo: Identifiable, Hashable {
    let id: String   // código ISO, por ejemplo "CZK"

    var nombre: String {
        let n = Locale.current.localizedString(forCurrencyCode: id) ?? id
        return n.prefix(1).uppercased() + n.dropFirst()
    }
}

enum Divisas {
    static let todas: [DivisaInfo] = Locale.commonISOCurrencyCodes.sorted().map { DivisaInfo(id: $0) }

    /// Moneda habitual de un país a partir de su código ISO de país ("CZ" -> "CZK").
    static func codigoParaPais(_ iso: String?) -> String? {
        guard let iso = iso, iso.count == 2 else { return nil }
        return Locale(identifier: "en_\(iso.uppercased())").currency?.identifier
    }
}

/// Convierte una tasa a texto editable sin notación científica.
func textoTasa(_ tasa: Double) -> String {
    var s = String(format: "%.8f", tasa)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}

@MainActor
final class ServicioDivisas: ObservableObject {
    /// 1 euro = X unidades de la divisa
    @Published private(set) var tasasPorEuro: [String: Double] = [:]
    @Published private(set) var ultimaActualizacion: Date? = nil
    @Published private(set) var cargando = false
    @Published private(set) var errorUltimaCarga: String? = nil

    private let claveTasas = "escapadas_tasas_v2"
    private let claveFecha = "escapadas_tasas_fecha_v2"

    private struct Respuesta: Decodable {
        let rates: [String: Double]?
    }

    init() {
        let d = UserDefaults.standard
        if let datos = d.data(forKey: claveTasas),
           let dic = try? JSONDecoder().decode([String: Double].self, from: datos) {
            tasasPorEuro = dic
        }
        ultimaActualizacion = d.object(forKey: claveFecha) as? Date
    }

    /// Valor de 1 unidad de `codigo` expresado en euros. nil si no hay tasa conocida.
    func tasaAEuros(de codigo: String) -> Double? {
        if codigo == "EUR" { return 1 }
        guard let porEuro = tasasPorEuro[codigo], porEuro > 0 else { return nil }
        return 1 / porEuro
    }

    func actualizarSiHaceFalta() async {
        if let f = ultimaActualizacion, !tasasPorEuro.isEmpty, Date().timeIntervalSince(f) < 6 * 3600 {
            return
        }
        await actualizar()
    }

    func actualizar() async {
        guard !cargando else { return }
        cargando = true
        defer { cargando = false }

        guard let url = URL(string: "https://open.er-api.com/v6/latest/EUR") else { return }
        var peticion = URLRequest(url: url)
        peticion.timeoutInterval = 10

        do {
            let (datos, respuesta) = try await URLSession.shared.data(for: peticion)
            guard let http = respuesta as? HTTPURLResponse, http.statusCode == 200 else {
                errorUltimaCarga = "El servicio de divisas no respondió"
                return
            }
            let r = try JSONDecoder().decode(Respuesta.self, from: datos)
            guard let tasas = r.rates, !tasas.isEmpty else {
                errorUltimaCarga = "Respuesta de divisas vacía"
                return
            }
            tasasPorEuro = tasas
            ultimaActualizacion = Date()
            errorUltimaCarga = nil
            let d = UserDefaults.standard
            if let datosTasas = try? JSONEncoder().encode(tasas) {
                d.set(datosTasas, forKey: claveTasas)
            }
            d.set(ultimaActualizacion, forKey: claveFecha)
        } catch {
            errorUltimaCarga = "No se pudieron actualizar las divisas (sin conexión)"
        }
    }
}
