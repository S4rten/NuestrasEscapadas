import SwiftUI

// ============================================================================
// FESTIVOS DEL DESTINO (date.nager.at: gratis y sin clave)
// Se guardan en el iPhone por país y año. Sirven para avisar en el Plan
// ("el 25 de diciembre es festivo: muchos museos y tiendas cierran") y para
// los horarios de apertura que dicen "festivos cerrado".
// ============================================================================

struct Festivo: Codable, Hashable {
    let date: String                        // "2026-12-25"
    let localName: String
    let name: String                        // en inglés
    let global: Bool?
    let counties: [String]?

    /// Nombre en español (los más habituales); si no, el inglés.
    var nombre: String {
        Festivo.traducciones[name] ?? name
    }

    /// Solo en algunas regiones del país.
    var regional: Bool { global == false }

    private static let traducciones: [String: String] = [
        "New Year's Day": "Año Nuevo",
        "New Year's Eve": "Nochevieja",
        "Epiphany": "Reyes",
        "Good Friday": "Viernes Santo",
        "Maundy Thursday": "Jueves Santo",
        "Holy Saturday": "Sábado Santo",
        "Easter Sunday": "Domingo de Pascua",
        "Easter Monday": "Lunes de Pascua",
        "Labour Day": "Día del Trabajo",
        "Labor Day": "Día del Trabajo",
        "May Day": "Primero de mayo",
        "Ascension Day": "Ascensión",
        "Whit Sunday": "Pentecostés",
        "Pentecost": "Pentecostés",
        "Whit Monday": "Lunes de Pentecostés",
        "Corpus Christi": "Corpus Christi",
        "Assumption Day": "La Asunción",
        "Assumption of Mary": "La Asunción",
        "All Saints' Day": "Todos los Santos",
        "All Souls' Day": "Día de Difuntos",
        "Immaculate Conception": "Inmaculada Concepción",
        "Christmas Eve": "Nochebuena",
        "Christmas Day": "Navidad",
        "St. Stephen's Day": "San Esteban",
        "Boxing Day": "Boxing Day (26 de diciembre)",
        "Independence Day": "Día de la Independencia",
        "National Day": "Fiesta nacional",
        "Liberation Day": "Día de la Liberación",
        "Republic Day": "Día de la República",
        "Constitution Day": "Día de la Constitución",
        "Thanksgiving Day": "Acción de Gracias",
        "Memorial Day": "Memorial Day",
        "Early May Bank Holiday": "Festivo de mayo",
        "Spring Bank Holiday": "Festivo de primavera",
        "Summer Bank Holiday": "Festivo de verano"
    ]
}

@MainActor
final class ServicioFestivos: ObservableObject {
    static let compartido = ServicioFestivos()

    /// "CZ-2026" -> festivos de ese año
    @Published private(set) var festivos: [String: [Festivo]] = [:]
    private var enCurso: Set<String> = []
    private var fallidoEn: [String: Date] = [:]
    private let claveCache = "escapadas_festivos_v1"

    private static let formatoDia: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        if let datos = UserDefaults.standard.data(forKey: claveCache),
           let guardados = try? JSONDecoder().decode([String: [Festivo]].self, from: datos) {
            festivos = guardados
        }
    }

    private static func clave(_ pais: String, _ ano: Int) -> String {
        "\(pais.uppercased())-\(ano)"
    }

    /// Descarga los festivos de los años que toca el viaje (si no están ya guardados).
    func cargar(para escapada: Escapada) async {
        let pais = escapada.paisCodigo.uppercased()
        guard pais.count == 2 else { return }
        let cal = Calendar.current
        let anos = Set([cal.component(.year, from: escapada.fechaInicio), cal.component(.year, from: escapada.fechaFin)])
        for ano in anos.sorted() {
            await cargar(pais: pais, ano: ano)
        }
    }

    func cargar(pais: String, ano: Int) async {
        let c = Self.clave(pais, ano)
        guard festivos[c] == nil, !enCurso.contains(c) else { return }
        if let f = fallidoEn[c], Date().timeIntervalSince(f) < 600 { return }
        guard let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(ano)/\(pais.uppercased())") else { return }
        enCurso.insert(c)
        var peticion = URLRequest(url: url)
        peticion.timeoutInterval = 12
        let resultado = try? await URLSession.shared.data(for: peticion)
        enCurso.remove(c)

        guard let resultado = resultado else {
            fallidoEn[c] = Date()
            return
        }
        let datos = resultado.0
        let estado = (resultado.1 as? HTTPURLResponse)?.statusCode ?? 0
        if estado == 200, let lista = try? JSONDecoder().decode([Festivo].self, from: datos) {
            festivos[c] = lista
        } else if estado == 204 || estado == 404 {
            festivos[c] = []                // país sin datos: no volver a preguntar
        } else {
            fallidoEn[c] = Date()
            return
        }
        if let codificados = try? JSONEncoder().encode(festivos) {
            UserDefaults.standard.set(codificados, forKey: claveCache)
        }
    }

    /// Festivo de ese día en ese país (nil si no lo es o no se sabe todavía).
    func festivo(pais: String, fecha: Date) -> Festivo? {
        let ano = Calendar.current.component(.year, from: fecha)
        let dia = Self.formatoDia.string(from: fecha)
        return festivos[Self.clave(pais, ano)]?.first { $0.date == dia }
    }

    /// Festivos que caen durante el viaje.
    func festivosDelViaje(_ escapada: Escapada) -> [(dia: Int, festivo: Festivo)] {
        let pais = escapada.paisCodigo.uppercased()
        guard pais.count == 2 else { return [] }
        var lista: [(dia: Int, festivo: Festivo)] = []
        for d in 1...escapada.totalDias {
            if let f = festivo(pais: pais, fecha: escapada.fechaParaDia(d)) {
                lista.append((dia: d, festivo: f))
            }
        }
        return lista
    }
}

/// Fila del Plan: "🎉 Festivo: Navidad (Vánoce)".
struct FilaFestivoDia: View {
    @ObservedObject private var servicio = ServicioFestivos.compartido
    let escapada: Escapada
    let dia: Int

    var body: some View {
        let pais = escapada.paisCodigo.uppercased()
        Group {
            if pais.count == 2, let f = servicio.festivo(pais: pais, fecha: escapada.fechaParaDia(dia)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("🎉 Festivo en \(Paises.nombre(pais)): \(f.nombre)")
                        .font(.subheadline.weight(.semibold))
                    Text(f.regional
                         ? "Solo en algunas regiones (\(f.localName)). Mirad si afecta a vuestra zona."
                         : "\(f.localName). Muchos museos, tiendas y oficinas pueden cerrar o abrir con otro horario.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: escapada.id) {
            await servicio.cargar(para: escapada)
        }
    }
}

/// Fila de la ficha del país: festivos que caen durante el viaje.
struct FilaFestivosViaje: View {
    @ObservedObject private var servicio = ServicioFestivos.compartido
    let escapada: Escapada

    var body: some View {
        let lista = servicio.festivosDelViaje(escapada)
        Group {
            if !lista.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Text("🎉")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Festivos durante el viaje")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(lista, id: \.dia) { item in
                            Text("Día \(item.dia) (\(escapada.fechaParaDia(item.dia).formatted(.dateTime.day().month(.abbreviated)))): \(item.festivo.nombre)\(item.festivo.regional ? " · regional" : "")")
                                .font(.subheadline)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .task(id: escapada.id) {
            await servicio.cargar(para: escapada)
        }
    }
}
