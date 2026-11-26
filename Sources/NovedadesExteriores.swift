import SwiftUI

// ============================================================================
// EXTERIORES: consulta en exteriores.gob.es las recomendaciones de viaje del
// país (fecha de la última actualización, notas importantes y avisos de
// "se desaconseja") y avisa si han cambiado después de planear el viaje.
// La última consulta se guarda en el iPhone por si la web va lenta o no hay red.
// ============================================================================

struct SeccionExteriores: Codable, Equatable, Identifiable {
    var titulo: String
    var texto: String
    var id: String { titulo }
}

struct InfoExteriores: Codable, Equatable {
    var pais: String = ""                   // nombre tal cual lo usa la web
    var actualizacion: String = ""          // "29 de octubre de 2026"
    var notas: String = ""                  // "Notas importantes" (puede no haber)
    var avisos: [String] = []               // frases con "se desaconseja…"
    var secciones: [SeccionExteriores] = []
    var url: String = ""
    var consultadaEn: Date = Date()

    var fechaActualizacion: Date? { Exteriores.fecha(actualizacion) }
}

@MainActor
final class ServicioExteriores: ObservableObject {
    static let compartido = ServicioExteriores()

    @Published private(set) var fichas: [String: InfoExteriores] = [:]     // por código ISO
    @Published private(set) var consultando: Set<String> = []
    @Published private(set) var errores: [String: String] = [:]

    private let claveCache = "escapadas_exteriores_v1"

    init() {
        if let datos = UserDefaults.standard.data(forKey: claveCache),
           let guardadas = try? JSONDecoder().decode([String: InfoExteriores].self, from: datos) {
            fichas = guardadas
        }
    }

    /// Consulta la web si no hay nada guardado o si lo guardado tiene más de 12 horas.
    func actualizarSiHaceFalta(_ iso: String, forzar: Bool = false) async {
        let codigo = iso.uppercased()
        guard !codigo.isEmpty, !consultando.contains(codigo) else { return }
        if !forzar, let f = fichas[codigo], Date().timeIntervalSince(f.consultadaEn) < 12 * 3600 { return }

        consultando.insert(codigo)
        errores[codigo] = nil
        var ultimoError = "No he encontrado este país en exteriores.gob.es."
        var encontrada = false

        for nombre in Exteriores.nombresCandidatos(codigo) {
            let resultado = await Exteriores.descargar(nombre: nombre)
            if case .ficha(let info) = resultado {
                fichas[codigo] = info
                guardar()
                encontrada = true
                break
            }
            if case .fallo(let texto) = resultado {
                ultimoError = texto
                break               // la web no responde: no tiene sentido probar otro nombre
            }
        }

        if !encontrada { errores[codigo] = ultimoError }
        consultando.remove(codigo)
    }

    private func guardar() {
        if let datos = try? JSONEncoder().encode(fichas) {
            UserDefaults.standard.set(datos, forKey: claveCache)
        }
    }
}

enum Exteriores {
    enum Resultado {
        case ficha(InfoExteriores)
        case noEncontrado
        case fallo(String)
    }

    static let paginaGeneral = "https://www.exteriores.gob.es/es/ServiciosAlCiudadano/Paginas/Recomendaciones-de-viaje.aspx"
    private static let paginaPais = "https://www.exteriores.gob.es/es/ServiciosAlCiudadano/Paginas/Detalle-recomendaciones-de-viaje.aspx"

    /// Países que la web llama distinto que iOS (comprobados en la propia web).
    private static let nombresWeb: [String: String] = [
        "CZ": "República Checa",
        "KR": "Corea",
        "VA": "Santa Sede",
        "CI": "Costa de Marfil",
        "MM": "Myanmar",
        "PS": "Palestina",
        "TR": "Turquía",
        "US": "Estados Unidos",
        "GB": "Reino Unido",
        "HK": "China",
        "MO": "China"
    ]

    static func nombresCandidatos(_ iso: String) -> [String] {
        var lista: [String] = []
        if let n = nombresWeb[iso] { lista.append(n) }
        if let n = Locale(identifier: "es_ES").localizedString(forRegionCode: iso), !lista.contains(n) {
            lista.append(n)
        }
        return lista
    }

    static func url(nombre: String) -> URL? {
        var c = URLComponents(string: paginaPais)
        c?.queryItems = [URLQueryItem(name: "trc", value: nombre)]
        return c?.url
    }

    /// La web a veces tarda mucho o da error: se intenta dos veces.
    static func descargar(nombre: String) async -> Resultado {
        guard let direccion = url(nombre: nombre) else { return .noEncontrado }
        var ultimo = "La web de Exteriores no responde ahora mismo. Probad más tarde."
        for intento in 0..<2 {
            if intento > 0 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            var peticion = URLRequest(url: direccion)
            peticion.timeoutInterval = 30
            do {
                let (datos, respuesta) = try await URLSession.shared.data(for: peticion)
                let estado = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
                guard estado == 200 else {
                    ultimo = "La web de Exteriores no responde ahora mismo (error \(estado)). Probad más tarde."
                    continue
                }
                let html = String(decoding: datos, as: UTF8.self)
                guard let info = interpretar(html, nombre: nombre, url: direccion.absoluteString) else {
                    return .noEncontrado
                }
                return .ficha(info)
            } catch {
                ultimo = "No se pudo conectar con exteriores.gob.es. Comprobad la conexión."
            }
        }
        return .fallo(ultimo)
    }

    // MARK: Lectura de la página

    static func interpretar(_ html: String, nombre: String, url: String) -> InfoExteriores? {
        // Si el país no existe, la web devuelve una página sin el bloque de fechas.
        guard html.contains("current-information") else { return nil }

        var info = InfoExteriores()
        info.pais = nombre
        info.url = url
        info.consultadaEn = Date()
        if let fecha = primerGrupo("ltima actualizaci[oó]n el ([^<]+)<", en: html) {
            info.actualizacion = limpiar(fecha)
        }

        // Apartados del desplegable: Notas importantes, Documentación y visados, Seguridad…
        let ns = html as NSString
        var secciones: [SeccionExteriores] = []
        if let regex = try? NSRegularExpression(pattern: "<h3[^>]*accordion__main[^>]*>") {
            let marcas = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
            for (i, marca) in marcas.enumerated() {
                let inicio = marca.range.location + marca.range.length
                let fin = i + 1 < marcas.count ? marcas[i + 1].range.location : min(ns.length, inicio + 30_000)
                guard fin > inicio else { continue }
                var trozo = ns.substring(with: NSRange(location: inicio, length: fin - inicio))
                if let corte = trozo.range(of: "<footer") {
                    trozo = String(trozo[..<corte.lowerBound])
                }
                let titulo = limpiar(String(trozo.prefix(while: { $0 != "<" })))
                guard !titulo.isEmpty else { continue }
                let cuerpo = trozo.range(of: "</h3>").map { String(trozo[$0.upperBound...]) } ?? trozo
                let texto = String(textoPlano(cuerpo).prefix(6000))
                if !texto.isEmpty {
                    secciones.append(SeccionExteriores(titulo: titulo, texto: texto))
                }
            }
        }
        info.secciones = secciones
        info.notas = secciones.first(where: { $0.titulo.lowercased().contains("notas") })?.texto ?? ""
        info.avisos = frasesConAviso(secciones)
        return info
    }

    /// Frases de "Notas importantes" y "Seguridad" que desaconsejan viajar a algún sitio.
    private static func frasesConAviso(_ secciones: [SeccionExteriores]) -> [String] {
        var frases: [String] = []
        for s in secciones {
            let titulo = s.titulo.lowercased()
            guard titulo.contains("notas") || titulo.contains("seguridad") else { continue }
            for trozo in s.texto.components(separatedBy: CharacterSet(charactersIn: ".\n")) {
                let frase = trozo.trimmingCharacters(in: .whitespaces)
                let minusculas = frase.lowercased()
                if minusculas.contains("desaconseja") || minusculas.contains("no viajar") {
                    frases.append(frase + ".")
                    if frases.count >= 3 { return frases }
                }
            }
        }
        return frases
    }

    static func textoPlano(_ html: String) -> String {
        var t = html
        t = t.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)</(p|div|li|h4|h2|tr)>", with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)<li[^>]*>", with: "\n• ", options: .regularExpression)
        t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        t = decodificarEntidades(t)
        t = t.replacingOccurrences(of: "\u{200B}", with: "")
        let lineas = t.components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: "[ \t\u{00A0}]+", with: " ", options: .regularExpression) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "•" }
        return lineas.joined(separator: "\n")
    }

    private static func limpiar(_ texto: String) -> String {
        decodificarEntidades(texto)
            .replacingOccurrences(of: "\u{200B}", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// &#160; &#58; &quot; &amp;… -> caracteres normales.
    private static func decodificarEntidades(_ texto: String) -> String {
        var t = texto
        if let regex = try? NSRegularExpression(pattern: "&#([xX]?)([0-9A-Fa-f]+);") {
            let ns = t as NSString
            var resultado = ""
            var ultimo = 0
            for m in regex.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
                resultado += ns.substring(with: NSRange(location: ultimo, length: m.range.location - ultimo))
                let esHex = m.range(at: 1).length > 0
                let numero = ns.substring(with: m.range(at: 2))
                if let valor = UInt32(numero, radix: esHex ? 16 : 10), let escalar = Unicode.Scalar(valor) {
                    resultado.append(Character(escalar))
                }
                ultimo = m.range.location + m.range.length
            }
            resultado += ns.substring(from: ultimo)
            t = resultado
        }
        let nombradas: [(String, String)] = [
            ("&nbsp;", " "), ("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")
        ]
        for (entidad, caracter) in nombradas {
            t = t.replacingOccurrences(of: entidad, with: caracter)
        }
        return t
    }

    private static func primerGrupo(_ patron: String, en texto: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: patron),
              let m = regex.firstMatch(in: texto, range: NSRange(texto.startIndex..., in: texto)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: texto) else { return nil }
        return String(texto[r])
    }

    /// "29 de octubre de 2026" -> fecha.
    static func fecha(_ texto: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "d 'de' MMMM 'de' yyyy"
        return f.date(from: texto.recortado.lowercased())
    }
}

// ============================================================================
// BLOQUE DENTRO DE LA FICHA DEL PAÍS
// ============================================================================

struct BloqueExteriores: View {
    let iso: String
    let escapada: Escapada
    @ObservedObject private var servicio = ServicioExteriores.compartido

    var body: some View {
        let ficha = servicio.fichas[iso]

        if let ficha = ficha {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    Text("🏛️")
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recomendaciones de Exteriores")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        if !ficha.actualizacion.isEmpty {
                            Text("Actualizadas el \(ficha.actualizacion)")
                                .font(.subheadline)
                        }
                        if Exteriores.cambioTrasPlanear(ficha, escapada: escapada) {
                            Text("🆕 Han cambiado después de planear el viaje: echadles un vistazo.")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                }

                ForEach(ficha.avisos, id: \.self) { aviso in
                    Text("⚠️ \(aviso)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !ficha.notas.isEmpty {
                    Text("📌 Notas importantes")
                        .font(.caption.bold())
                        .padding(.top, 2)
                    Text(ficha.notas)
                        .font(.caption)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Consultado \(ficha.consultadaEn.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)

            NavigationLink {
                DetalleExterioresView(info: ficha, iso: iso)
            } label: {
                Label("Ver todas las recomendaciones", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline)
            }
        }

        if servicio.consultando.contains(iso) {
            HStack(spacing: 8) {
                ProgressView()
                Text(ficha == nil ? "Consultando exteriores.gob.es…" : "Buscando cambios en exteriores.gob.es…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let error = servicio.errores[iso] {
            VStack(alignment: .leading, spacing: 4) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Volver a consultar") {
                    Task { await servicio.actualizarSiHaceFalta(iso, forzar: true) }
                }
                .font(.caption.bold())
                .buttonStyle(.borderless)
            }
        }
    }
}

extension Exteriores {
    /// true si la web se actualizó después del día en que se creó la escapada.
    static func cambioTrasPlanear(_ info: InfoExteriores, escapada: Escapada) -> Bool {
        guard let f = info.fechaActualizacion else { return false }
        return f > escapada.creadaEn.inicioDelDia
    }
}

struct DetalleExterioresView: View {
    let info: InfoExteriores
    let iso: String

    var body: some View {
        List {
            Section {
                if !info.actualizacion.isEmpty {
                    Text("Última actualización: \(info.actualizacion)")
                        .font(.subheadline)
                }
                if let url = URL(string: info.url) {
                    Link(destination: url) {
                        Label("Abrir en exteriores.gob.es", systemImage: "safari")
                    }
                }
            } footer: {
                Text("Copia de la web del Ministerio de Asuntos Exteriores para viajeros españoles. Ante cualquier duda, manda lo que diga la web.")
            }

            ForEach(info.secciones) { s in
                Section(s.titulo) {
                    Text(s.texto)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("\(Paises.bandera(iso)) \(info.pais)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
