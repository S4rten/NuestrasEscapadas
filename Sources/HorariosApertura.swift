import SwiftUI

// ============================================================================
// HORARIOS DE APERTURA DE LOS PLANES (OpenStreetMap, servicio Overpass: gratis)
// Para cada plan situado en el mapa se busca muy cerca un sitio con el mismo
// nombre que tenga "opening_hours". Así se avisa de "⚠️ Cerrado ese día" o de
// que a la hora elegida está cerrado. Se guarda en el iPhone 3 semanas.
// ============================================================================

struct HorarioGuardado: Codable, Equatable {
    var clave: String                       // nombre + posición del plan (si cambian, se vuelve a buscar)
    var horario: String                     // "Tu-Su 10:00-18:00; Mo off" ("" = no se encontró)
    var nombreOSM: String
    var consultadoEn: Date
}

@MainActor
final class ServicioHorarios: ObservableObject {
    static let compartido = ServicioHorarios()

    @Published private(set) var horarios: [String: HorarioGuardado] = [:]     // por ID del plan
    private var cola: [Actividad] = []
    private var trabajando = false
    private var pausaHasta: Date? = nil
    private let claveCache = "escapadas_horarios_osm_v1"

    init() {
        if let datos = UserDefaults.standard.data(forKey: claveCache),
           let guardados = try? JSONDecoder().decode([String: HorarioGuardado].self, from: datos) {
            horarios = guardados
        }
    }

    static func clave(de a: Actividad) -> String {
        String(format: "%@|%.4f|%.4f", a.nombreSitio.recortado.lowercased(), a.latitud ?? 0, a.longitud ?? 0)
    }

    /// Horario conocido de un plan (solo si sigue siendo el mismo sitio).
    func horario(de a: Actividad) -> HorarioGuardado? {
        guard let h = horarios[a.id], h.clave == Self.clave(de: a) else { return nil }
        return h
    }

    /// Pide el horario de un plan (en cola: uno detrás de otro para no saturar el servicio).
    func pedir(_ a: Actividad) {
        guard a.latitud != nil, a.longitud != nil else { return }
        if let h = horario(de: a), Date().timeIntervalSince(h.consultadoEn) < 21 * 24 * 3600 { return }
        guard !cola.contains(where: { $0.id == a.id }) else { return }
        cola.append(a)
        if !trabajando {
            trabajando = true
            Task { await procesarCola() }
        }
    }

    private func procesarCola() async {
        while !cola.isEmpty {
            if let p = pausaHasta, p > Date() { break }
            let a = cola.removeFirst()
            if let encontrado = await buscar(a) {
                horarios[a.id] = encontrado
                if let datos = try? JSONEncoder().encode(horarios) {
                    UserDefaults.standard.set(datos, forKey: claveCache)
                }
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
        cola.removeAll()
        trabajando = false
    }

    /// nil = no se pudo preguntar (se intentará otro día); horario vacío = no hay datos.
    private func buscar(_ a: Actividad) async -> HorarioGuardado? {
        guard let lat = a.latitud, let lon = a.longitud else { return nil }
        let consulta = String(format: "[out:json][timeout:20];nwr(around:90,%.6f,%.6f)[\"opening_hours\"];out tags 40;", lat, lon)
        var c = URLComponents(string: "https://overpass-api.de/api/interpreter")
        c?.queryItems = [URLQueryItem(name: "data", value: consulta)]
        guard let url = c?.url else { return nil }
        var peticion = URLRequest(url: url)
        peticion.timeoutInterval = 25
        peticion.setValue("NuestrasEscapadas/1.0 (app privada para iOS)", forHTTPHeaderField: "User-Agent")

        guard let resultado = try? await URLSession.shared.data(for: peticion) else { return nil }
        let estado = (resultado.1 as? HTTPURLResponse)?.statusCode ?? 0
        if estado == 429 || estado == 504 {
            pausaHasta = Date().addingTimeInterval(120)       // el servicio pide calma
            return nil
        }
        guard estado == 200,
              let json = (try? JSONSerialization.jsonObject(with: resultado.0)) as? [String: Any],
              let elementos = json["elements"] as? [[String: Any]] else { return nil }

        let candidatos = elementos.compactMap { $0["tags"] as? [String: String] }
        let elegido = HorarioOSM.elegir(plan: a.nombreSitio, entre: candidatos)
        return HorarioGuardado(
            clave: Self.clave(de: a),
            horario: elegido?["opening_hours"] ?? "",
            nombreOSM: elegido?["name"] ?? "",
            consultadoEn: Date()
        )
    }
}

// ============================================================================
// LECTURA DEL FORMATO "opening_hours" (lo más habitual: días, horas, meses,
// festivos y "off"). Si hay algo raro, se enseña el texto tal cual.
// ============================================================================

enum HorarioOSM {
    enum Estado: Equatable {
        case abierto([ClosedRange<Int>])    // minutos desde medianoche (puede pasar de 1440)
        case cerrado
        case desconocido
    }

    private struct Regla {
        var meses: Set<Int>? = nil
        var fechas: [(mes: Int, dia: Int)] = []
        var dias: Set<Int>? = nil           // 1 = domingo … 7 = sábado (como Calendar)
        var soloFestivo = false
        var conFestivo = false
        var cerrado = false
        var tramos: [ClosedRange<Int>] = []
    }

    private static let codigosDia = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    private static let diaCalendario = [2, 3, 4, 5, 6, 7, 1]       // Mo -> 2 … Su -> 1
    private static let codigosMes = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    // MARK: Elegir el sitio de OpenStreetMap que es el plan

    private static let genericas: Set<String> = [
        "museo", "museum", "iglesia", "church", "plaza", "parque", "restaurante", "restaurant",
        "palacio", "castillo", "catedral", "torre", "jardin", "jardines", "mercado", "galeria",
        "centro", "nacional", "national", "visita", "entrada", "tour"
    ]

    private static let tiposVisitables = ["museum", "attraction", "gallery", "zoo", "aquarium", "theme_park", "viewpoint"]
    private static let pistasVisitables = [
        "museo", "galeria", "castillo", "palacio", "catedral", "iglesia", "basilica", "torre", "zoo",
        "acuario", "jardin", "monasterio", "templo", "mezquita", "sinagoga", "museum", "castle", "palace"
    ]

    static func normalizar(_ t: String) -> String {
        let sinTildes = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        let soloLetras = sinTildes.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(soloLetras).split(separator: " ").joined(separator: " ")
    }

    private static func palabras(_ t: String) -> Set<String> {
        Set(t.split(separator: " ").map(String.init).filter { $0.count >= 5 && !genericas.contains($0) })
    }

    /// El candidato cuyo nombre coincide con el del plan (o el único sitio turístico, si el plan lo es).
    static func elegir(plan: String, entre candidatos: [[String: String]]) -> [String: String]? {
        let p = normalizar(plan)
        guard !p.isEmpty else { return nil }
        let pPalabras = palabras(p)
        let clavesNombre = ["name", "name:es", "name:en", "alt_name", "official_name", "short_name", "int_name"]

        for c in candidatos {
            for clave in clavesNombre {
                guard let nombre = c[clave] else { continue }
                let n = normalizar(nombre)
                guard n.count >= 3 else { continue }
                if p == n || p.contains(n) || n.contains(p) { return c }
                if !pPalabras.isDisjoint(with: palabras(n)) { return c }
            }
        }

        // Sin coincidencia de nombre: solo si el plan es un sitio visitable y cerca hay uno solo.
        guard pistasVisitables.contains(where: { p.contains($0) }) else { return nil }
        let visitables = candidatos.filter { c in
            tiposVisitables.contains(c["tourism"] ?? "") || c["historic"] != nil || c["amenity"] == "place_of_worship"
        }
        return visitables.count == 1 ? visitables.first : nil
    }

    // MARK: Interpretar el horario

    static func estado(_ texto: String, fecha: Date, esFestivo: Bool) -> Estado {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty else { return .desconocido }
        if limpio == "24/7" { return .abierto([0...1440]) }

        let cal = Calendar.current
        let diaSemana = cal.component(.weekday, from: fecha)
        let mes = cal.component(.month, from: fecha)
        let diaMes = cal.component(.day, from: fecha)

        var resultado: Estado = .cerrado        // lo que no se menciona, cerrado
        for bruta in limpio.replacingOccurrences(of: "||", with: ";").components(separatedBy: ";") {
            let regla = bruta.trimmingCharacters(in: .whitespaces)
            if regla.isEmpty { continue }
            guard let r = interpretar(regla) else { return .desconocido }
            if let m = r.meses, !m.contains(mes) { continue }
            if !r.fechas.isEmpty && !r.fechas.contains(where: { $0.mes == mes && $0.dia == diaMes }) { continue }
            let aplica: Bool
            if r.soloFestivo {
                aplica = esFestivo
            } else if let d = r.dias {
                aplica = d.contains(diaSemana) || (r.conFestivo && esFestivo)
            } else {
                aplica = true
            }
            if aplica {
                resultado = r.cerrado ? .cerrado : .abierto(r.tramos.isEmpty ? [0...1440] : r.tramos)
            }
        }
        return resultado
    }

    private static func interpretar(_ regla: String) -> Regla? {
        var r = Regla()
        var piezas = regla.split(separator: " ").map(String.init).filter { !$0.isEmpty }

        // Meses al principio: "Apr-Oct", "Dec 24", "Jan,Feb".
        if let primera = piezas.first, let listaMeses = meses(primera) {
            piezas.removeFirst()
            if let siguiente = piezas.first, let d = Int(siguiente), (1...31).contains(d), listaMeses.count == 1, let m = listaMeses.first {
                r.fechas = [(mes: m, dia: d)]
                piezas.removeFirst()
            } else {
                r.meses = listaMeses
            }
        }

        // Días de la semana y festivos: "Mo-Fr", "Sa,Su", "Su,PH", "PH".
        if let primera = piezas.first, primera.first?.isLetter == true,
           !["off", "closed"].contains(primera.lowercased()) {
            var dias: Set<Int> = []
            for parte in primera.split(separator: ",").map(String.init) {
                if parte == "PH" {
                    r.conFestivo = true
                } else if let rango = rangoDias(parte) {
                    dias.formUnion(rango)
                } else {
                    return nil                  // SH, "week", "easter"…: no lo sabemos leer
                }
            }
            if dias.isEmpty && r.conFestivo {
                r.soloFestivo = true
            } else {
                r.dias = dias
            }
            piezas.removeFirst()
        }

        // Horas o cerrado.
        for pieza in piezas {
            let p = pieza.lowercased()
            if p == "off" || p == "closed" {
                r.cerrado = true
                continue
            }
            for tramo in pieza.split(separator: ",").map(String.init) {
                guard let t = tramoHoras(tramo) else { return nil }
                r.tramos.append(t)
            }
        }
        return r
    }

    private static func meses(_ texto: String) -> Set<Int>? {
        var resultado: Set<Int> = []
        for parte in texto.split(separator: ",").map(String.init) {
            let extremos = parte.split(separator: "-").map(String.init)
            guard let primero = extremos.first, let a = codigosMes.firstIndex(of: primero) else { return nil }
            if extremos.count == 2, let b = codigosMes.firstIndex(of: extremos[1]) {
                var i = a
                while true {
                    resultado.insert(i + 1)
                    if i == b { break }
                    i = (i + 1) % 12
                }
            } else if extremos.count == 1 {
                resultado.insert(a + 1)
            } else {
                return nil
            }
        }
        return resultado.isEmpty ? nil : resultado
    }

    private static func rangoDias(_ texto: String) -> Set<Int>? {
        let extremos = texto.split(separator: "-").map(String.init)
        guard let primero = extremos.first, let a = codigosDia.firstIndex(of: primero) else { return nil }
        if extremos.count == 1 { return [diaCalendario[a]] }
        guard extremos.count == 2, let b = codigosDia.firstIndex(of: extremos[1]) else { return nil }
        var resultado: Set<Int> = []
        var i = a
        while true {
            resultado.insert(diaCalendario[i])
            if i == b { break }
            i = (i + 1) % 7
        }
        return resultado
    }

    /// "09:00-18:00" -> 540...1080. "20:00-02:00" -> 1200...1560 (pasa de medianoche).
    private static func tramoHoras(_ texto: String) -> ClosedRange<Int>? {
        let extremos = texto.split(separator: "-").map(String.init)
        guard extremos.count == 2, let a = minutos(extremos[0]), var b = minutos(extremos[1]) else { return nil }
        if b <= a { b += 1440 }
        return a...b
    }

    private static func minutos(_ texto: String) -> Int? {
        let partes = texto.split(separator: ":").map(String.init)
        guard partes.count == 2, let h = Int(partes[0]), let m = Int(partes[1]), (0...24).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    static func hhmm(_ minutos: Int) -> String {
        let m = minutos % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// "Abre 10:00–14:00 y 16:00–20:00"
    static func textoAbierto(_ tramos: [ClosedRange<Int>]) -> String {
        if tramos.contains(where: { $0.lowerBound == 0 && $0.upperBound >= 1440 }) { return "Abierto todo el día" }
        let textos = tramos.map { "\(hhmm($0.lowerBound))–\(hhmm($0.upperBound))" }
        return "Abre " + textos.joined(separator: " y ")
    }

    /// El texto original con los días en español ("Mo-Fr 09:00-18:00" -> "lu-vi 09:00-18:00").
    static func traducir(_ texto: String) -> String {
        var t = texto
        let cambios = [("Mo", "lu"), ("Tu", "ma"), ("We", "mi"), ("Th", "ju"), ("Fr", "vi"), ("Sa", "sá"), ("Su", "do"),
                       ("PH", "festivos"), ("off", "cerrado"), ("closed", "cerrado")]
        for (de, a) in cambios {
            t = t.replacingOccurrences(of: "\\b\(de)\\b", with: a, options: .regularExpression)
        }
        return t
    }
}

/// Línea bajo cada plan de la línea del tiempo con su horario de ese día.
struct FilaHorarioPlan: View {
    @ObservedObject private var servicio = ServicioHorarios.compartido
    @ObservedObject private var festivos = ServicioFestivos.compartido
    let actividad: Actividad
    let fecha: Date
    let pais: String

    var body: some View {
        Group {
            if let h = servicio.horario(de: actividad), !h.horario.isEmpty {
                let esFestivo = festivos.festivo(pais: pais, fecha: fecha) != nil
                let estado = HorarioOSM.estado(h.horario, fecha: fecha, esFestivo: esFestivo)
                switch estado {
                case .cerrado:
                    Text("⚠️ Cerrado ese día\(esFestivo ? " (es festivo)" : "") · según OpenStreetMap")
                        .font(.caption2.bold())
                        .foregroundStyle(.red)
                case .abierto(let tramos):
                    if let aviso = avisoHora(tramos) {
                        Text("⚠️ \(aviso)")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    } else {
                        Text("🕐 \(HorarioOSM.textoAbierto(tramos))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                case .desconocido:
                    Text("🕐 \(HorarioOSM.traducir(h.horario))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .onAppear { servicio.pedir(actividad) }
    }

    /// Si el plan tiene hora y a esa hora está cerrado.
    private func avisoHora(_ tramos: [ClosedRange<Int>]) -> String? {
        guard let hora = actividad.hora, !actividad.todoElDia else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: hora)
        let m = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let abierto = tramos.contains { $0.contains(m) || $0.contains(m + 1440) }
        return abierto ? nil : "A esa hora está cerrado (\(HorarioOSM.textoAbierto(tramos).lowercased()))"
    }
}
