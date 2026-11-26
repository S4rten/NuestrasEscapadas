import SwiftUI

// ============================================================================
// TIEMPO PREVISTO EN EL DESTINO (api.open-meteo.com: gratis y sin clave)
// La previsión llega hasta 16 días vista; se guarda en memoria 3 horas.
// ============================================================================

struct PrevisionDia {
    let codigo: Int
    let maxima: Double?
    let minima: Double?
    let probabilidadLluvia: Int?

    /// Códigos meteorológicos WMO que devuelve Open-Meteo.
    var emoji: String {
        switch codigo {
        case 0: return "☀️"
        case 1, 2: return "🌤️"
        case 3: return "☁️"
        case 45, 48: return "🌫️"
        case 51...57: return "🌦️"
        case 61...67: return "🌧️"
        case 71...77: return "🌨️"
        case 80...82: return "🌦️"
        case 85, 86: return "🌨️"
        case 95...99: return "⛈️"
        default: return "🌡️"
        }
    }

    var descripcion: String {
        switch codigo {
        case 0: return "Despejado"
        case 1, 2: return "Poco nuboso"
        case 3: return "Nublado"
        case 45, 48: return "Niebla"
        case 51...57: return "Llovizna"
        case 61...67: return "Lluvia"
        case 71...77: return "Nieve"
        case 80...82: return "Chubascos"
        case 85, 86: return "Chubascos de nieve"
        case 95...99: return "Tormenta"
        default: return "Variable"
        }
    }

    var textoTemperaturas: String {
        let maxTexto = maxima.map { "\(Int($0.rounded()))°" } ?? "–"
        let minTexto = minima.map { "\(Int($0.rounded()))°" } ?? "–"
        return "\(maxTexto) / \(minTexto)"
    }
}

private struct RespuestaOpenMeteo: Decodable {
    struct Diario: Decodable {
        let time: [String]
        let weather_code: [Int?]?
        let temperature_2m_max: [Double?]?
        let temperature_2m_min: [Double?]?
        let precipitation_probability_max: [Int?]?
    }
    let daily: Diario
}

@MainActor
final class ServicioTiempo: ObservableObject {
    static let compartido = ServicioTiempo()

    /// lugar -> "yyyy-MM-dd" -> previsión
    @Published private(set) var previsiones: [String: [String: PrevisionDia]] = [:]
    /// Lugares cuya última carga falló (sin conexión, servicio caído…).
    @Published private(set) var fallidos: Set<String> = []
    private var cargadoEn: [String: Date] = [:]
    private var enCurso: Set<String> = []

    /// Días con previsión disponible desde hoy.
    static let diasDePrevision = 15

    private static func claveLugar(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.2f,%.2f", lat, lon)
    }

    private static let formatoDia: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func prevision(lat: Double, lon: Double, fecha: Date) -> PrevisionDia? {
        previsiones[Self.claveLugar(lat, lon)]?[Self.formatoDia.string(from: fecha)]
    }

    func haFallado(lat: Double, lon: Double) -> Bool {
        fallidos.contains(Self.claveLugar(lat, lon))
    }

    func cargar(lat: Double, lon: Double) async {
        let clave = Self.claveLugar(lat, lon)
        if let ultima = cargadoEn[clave], Date().timeIntervalSince(ultima) < 3 * 3600 { return }
        guard !enCurso.contains(clave) else { return }
        enCurso.insert(clave)
        defer { enCurso.remove(clave) }

        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        comps?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "16")
        ]
        guard let url = comps?.url,
              let respuesta = try? await URLSession.shared.data(from: url),
              let datos = try? JSONDecoder().decode(RespuestaOpenMeteo.self, from: respuesta.0) else {
            fallidos.insert(clave)
            return
        }
        fallidos.remove(clave)

        let d = datos.daily
        var mapa: [String: PrevisionDia] = [:]
        for (i, dia) in d.time.enumerated() {
            mapa[dia] = PrevisionDia(
                codigo: Self.valor(d.weather_code, i) ?? -1,
                maxima: Self.valor(d.temperature_2m_max, i),
                minima: Self.valor(d.temperature_2m_min, i),
                probabilidadLluvia: Self.valor(d.precipitation_probability_max, i)
            )
        }
        previsiones[clave] = mapa
        cargadoEn[clave] = Date()
    }

    private static func valor<T>(_ lista: [T?]?, _ i: Int) -> T? {
        guard let lista = lista, i >= 0, i < lista.count else { return nil }
        return lista[i]
    }
}

/// Tiempo previsto para un día del viaje (pestaña Plan).
struct SeccionTiempoDia: View {
    @ObservedObject private var tiempo = ServicioTiempo.compartido
    let escapada: Escapada
    let dia: Int

    var body: some View {
        let fecha = escapada.fechaParaDia(dia)
        let diasHastaFecha = Calendar.current.dateComponents([.day], from: Date().inicioDelDia, to: fecha).day ?? 0

        if let lat = escapada.latitud, let lon = escapada.longitud, diasHastaFecha >= 0 {
            Section {
                Group {
                    contenido(lat: lat, lon: lon, fecha: fecha, diasHastaFecha: diasHastaFecha)
                }
                .task(id: "\(lat),\(lon)") {
                    await tiempo.cargar(lat: lat, lon: lon)
                }
            } header: {
                Text("Tiempo en \(escapada.destino) · Día \(dia)")
            }
        }
    }

    @ViewBuilder
    private func contenido(lat: Double, lon: Double, fecha: Date, diasHastaFecha: Int) -> some View {
                if let p = tiempo.prevision(lat: lat, lon: lon, fecha: fecha) {
                    HStack(spacing: 12) {
                        Text(p.emoji)
                            .font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.descripcion)
                                .font(.subheadline.weight(.semibold))
                            Text("Máx / mín: \(p.textoTemperaturas)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let lluvia = p.probabilidadLluvia {
                            Label("\(lluvia) %", systemImage: "drop.fill")
                                .font(.caption.bold())
                                .foregroundStyle(lluvia >= 50 ? Color.blue : Color.secondary)
                        }
                    }
                } else if diasHastaFecha > ServicioTiempo.diasDePrevision {
                    Text("La previsión del tiempo aparece unos \(ServicioTiempo.diasDePrevision) días antes. Faltan \(diasHastaFecha) días.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if tiempo.haFallado(lat: lat, lon: lon) {
                    Text("No se pudo cargar el tiempo. Se volverá a intentar al abrir el plan con conexión.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Buscando el tiempo en \(escapada.destino)…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
    }
}
