import SwiftUI
import CoreLocation

// ============================================================================
// HORA DEL DESTINO
//  · Zona horaria de cada destino: se averigua por sus coordenadas una vez y se
//    guarda en el iPhone ("allí son 2 h menos").
//  · Vuelos: cada hora se enseña en la zona de su aeropuerto, como en el billete,
//    aunque el iPhone esté en otra zona.
// ============================================================================

extension TimeZone {
    /// Zona por su identificador ("Europe/Prague"). Vacío o desconocido = la del iPhone.
    static func deIdentificador(_ id: String) -> TimeZone {
        TimeZone(identifier: id) ?? .current
    }

    /// "Nueva York" a partir de "America/New_York" (solo para mostrar).
    var ciudadLegible: String {
        let ultimo = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return ultimo.replacingOccurrences(of: "_", with: " ")
    }
}

extension Date {
    /// "10:35" en la zona indicada.
    func hora(en zona: TimeZone) -> String {
        formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zona))
    }

    /// "20 dic 2026" en la zona indicada.
    func dia(en zona: TimeZone) -> String {
        formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: zona))
    }

    /// La misma hora "de reloj" (día, hora y minuto) pasada de una zona a otra.
    /// Así no se mueve lo que se escribió cuando después se sabe en qué zona estaba.
    func mismaHoraDeReloj(de origen: TimeZone, a destino: TimeZone) -> Date {
        guard origen.identifier != destino.identifier else { return self }
        var calOrigen = Calendar(identifier: .gregorian)
        calOrigen.timeZone = origen
        var calDestino = Calendar(identifier: .gregorian)
        calDestino.timeZone = destino
        let c = calOrigen.dateComponents([.year, .month, .day, .hour, .minute], from: self)
        return calDestino.date(from: c) ?? self
    }
}

extension Vuelo {
    var zonaDeSalida: TimeZone { TimeZone.deIdentificador(zonaSalida) }
    var zonaDeLlegada: TimeZone { TimeZone.deIdentificador(zonaLlegada) }

    /// Hora de salida y de llegada en la hora local de cada aeropuerto.
    var horaSalidaLocal: String { fechaHoraSalida.hora(en: zonaDeSalida) }
    var horaLlegadaLocal: String { fechaHoraLlegada.hora(en: zonaDeLlegada) }
    var diaSalidaLocal: String { fechaHoraSalida.dia(en: zonaDeSalida) }

    /// Duración real: la guardada o, si se saben las dos zonas, la diferencia entre horas.
    var minutosDeVuelo: Int? {
        if duracionMinutos > 0 { return duracionMinutos }
        guard !zonaSalida.isEmpty, !zonaLlegada.isEmpty else { return nil }
        let m = Int((fechaHoraLlegada.timeIntervalSince(fechaHoraSalida) / 60).rounded())
        return (m > 0 && m < 24 * 60) ? m : nil
    }

    /// true si la salida o la llegada se enseñan en una zona distinta a la del iPhone.
    var tieneHoraLocalDistinta: Bool {
        let actual = TimeZone.current.identifier
        return (!zonaSalida.isEmpty && zonaSalida != actual) || (!zonaLlegada.isEmpty && zonaLlegada != actual)
    }

    /// ¿Sale este vuelo el día indicado (contando en la hora local de su aeropuerto)?
    func saleElDia(_ fecha: Date) -> Bool {
        var calSalida = Calendar(identifier: .gregorian)
        calSalida.timeZone = zonaDeSalida
        let dSalida = calSalida.dateComponents([.year, .month, .day], from: fechaHoraSalida)
        let dDia = Calendar.current.dateComponents([.year, .month, .day], from: fecha)
        return dSalida.year == dDia.year && dSalida.month == dDia.month && dSalida.day == dDia.day
    }
}

// ============================================================================
// ZONA DE CADA DESTINO (por coordenadas, guardada en el iPhone)
// ============================================================================

@MainActor
final class ZonasDestino: ObservableObject {
    static let compartido = ZonasDestino()

    /// "lat,lon" -> identificador de zona
    @Published private(set) var zonas: [String: String] = [:]
    private var enCurso: Set<String> = []
    private let claveCache = "escapadas_zonas_destino_v1"

    init() {
        zonas = (UserDefaults.standard.dictionary(forKey: claveCache) as? [String: String]) ?? [:]
    }

    static func clave(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.2f,%.2f", lat, lon)
    }

    func zona(lat: Double, lon: Double) -> TimeZone? {
        zonas[Self.clave(lat, lon)].flatMap { TimeZone(identifier: $0) }
    }

    func zona(de escapada: Escapada) -> TimeZone? {
        guard let lat = escapada.latitud, let lon = escapada.longitud else { return nil }
        return zona(lat: lat, lon: lon)
    }

    /// Averigua (una sola vez) la zona horaria de unas coordenadas.
    @discardableResult
    func averiguar(lat: Double, lon: Double) async -> TimeZone? {
        let c = Self.clave(lat, lon)
        if let ya = zona(lat: lat, lon: lon) { return ya }
        guard !enCurso.contains(c) else { return nil }
        enCurso.insert(c)
        let marcas = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon))
        enCurso.remove(c)
        guard let encontrada = marcas?.first?.timeZone else { return nil }
        zonas[c] = encontrada.identifier
        UserDefaults.standard.set(zonas, forKey: claveCache)
        return encontrada
    }
}

/// "🕐 En Londres son las 14:05 (1 h menos que aquí)". No sale nada si la hora es la misma.
struct TextoHoraDestino: View {
    let escapada: Escapada
    @ObservedObject private var zonas = ZonasDestino.compartido

    var body: some View {
        TimelineView(.everyMinute) { contexto in
            if let texto = TextoHoraDestino.texto(zona: zonas.zona(de: escapada), ahora: contexto.date, destino: escapada.destino) {
                Text(texto)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: "\(escapada.latitud ?? 0),\(escapada.longitud ?? 0)") {
            if let lat = escapada.latitud, let lon = escapada.longitud {
                await zonas.averiguar(lat: lat, lon: lon)
            }
        }
    }

    static func texto(zona: TimeZone?, ahora: Date, destino: String) -> String? {
        guard let zona = zona else { return nil }
        let diferencia = zona.secondsFromGMT(for: ahora) - TimeZone.current.secondsFromGMT(for: ahora)
        guard diferencia != 0 else { return nil }
        let horas = abs(Double(diferencia) / 3600)
        let cantidad = horas.rounded() == horas
            ? "\(Int(horas)) h"
            : String(format: "%.1f h", horas).replacingOccurrences(of: ".", with: ",")
        let sentido = diferencia > 0 ? "más" : "menos"
        let lugar = destino.isEmpty ? "el destino" : destino
        return "🕐 En \(lugar) son las \(ahora.hora(en: zona)) (\(cantidad) \(sentido) que aquí)"
    }
}
