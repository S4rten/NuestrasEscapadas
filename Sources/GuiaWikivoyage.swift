import SwiftUI

// ============================================================================
// GUÍA DEL DESTINO (Wikivoyage: libre, gratis y sin clave)
//  · "Del aeropuerto al centro": la parte de Llegar › En avión.
//  · "Qué ver": los sitios de la sección Ver, para pasarlos a vuestras ideas.
// Primero se busca en español; si falta algo, se completa con la versión inglesa.
// Se guarda en el iPhone dos semanas.
// ============================================================================

struct GuiaDestino: Codable, Equatable {
    var titulo: String = ""
    var url: String = ""
    var llegar: String = ""
    var llegarEnIngles = false
    var ver: [String] = []
    var verEnIngles = false
    var consultadaEn: Date = Date()
}

@MainActor
final class ServicioGuias: ObservableObject {
    static let compartido = ServicioGuias()

    @Published private(set) var guias: [String: GuiaDestino] = [:]       // por destino (normalizado)
    @Published private(set) var consultando: Set<String> = []
    @Published private(set) var sinGuia: Set<String> = []
    private var fallidaEn: [String: Date] = [:]
    private let claveCache = "escapadas_guias_wikivoyage_v1"

    init() {
        if let datos = UserDefaults.standard.data(forKey: claveCache),
           let guardadas = try? JSONDecoder().decode([String: GuiaDestino].self, from: datos) {
            guias = guardadas
        }
    }

    static func clave(_ destino: String) -> String {
        HorarioOSM.normalizar(destino)
    }

    func guia(_ destino: String) -> GuiaDestino? {
        guias[Self.clave(destino)]
    }

    func cargar(destino: String, forzar: Bool = false) async {
        let c = Self.clave(destino)
        guard !c.isEmpty, !consultando.contains(c) else { return }
        if !forzar, let g = guias[c], Date().timeIntervalSince(g.consultadaEn) < 14 * 24 * 3600 { return }
        if !forzar, let f = fallidaEn[c], Date().timeIntervalSince(f) < 3600 { return }

        consultando.insert(c)
        var guia = GuiaDestino()
        var tituloIngles: String? = nil

        if let es = await Wikivoyage.pagina(idioma: "es", titulo: destino) {
            guia.titulo = es.titulo
            guia.url = Wikivoyage.direccion(idioma: "es", titulo: es.titulo)
            guia.llegar = Wikivoyage.textoAeropuerto(es.extracto, idioma: "es")
            guia.ver = Wikivoyage.sitios(es.wikitext, idioma: "es")
            tituloIngles = es.tituloIngles
        }
        if guia.llegar.isEmpty || guia.ver.count < 3 {
            if let en = await Wikivoyage.pagina(idioma: "en", titulo: tituloIngles ?? destino) {
                if guia.llegar.isEmpty {
                    guia.llegar = Wikivoyage.textoAeropuerto(en.extracto, idioma: "en")
                    guia.llegarEnIngles = !guia.llegar.isEmpty
                }
                let sitiosIngles = Wikivoyage.sitios(en.wikitext, idioma: "en")
                if guia.ver.count < 3 && sitiosIngles.count > guia.ver.count {
                    guia.ver = sitiosIngles
                    guia.verEnIngles = true
                }
                if guia.titulo.isEmpty {
                    guia.titulo = en.titulo
                    guia.url = Wikivoyage.direccion(idioma: "en", titulo: en.titulo)
                }
            }
        }
        consultando.remove(c)

        guard !guia.titulo.isEmpty, !(guia.llegar.isEmpty && guia.ver.isEmpty) else {
            sinGuia.insert(c)
            fallidaEn[c] = Date()
            return
        }
        guia.consultadaEn = Date()
        guias[c] = guia
        sinGuia.remove(c)
        if let datos = try? JSONEncoder().encode(guias) {
            UserDefaults.standard.set(datos, forKey: claveCache)
        }
    }
}

enum Wikivoyage {
    struct Pagina {
        let titulo: String
        let extracto: String                // texto plano con los títulos "== Llegar =="
        let wikitext: String
        let tituloIngles: String?
    }

    private struct Seccion {
        let nivel: Int
        let titulo: String
        var texto: String
    }

    static func direccion(idioma: String, titulo: String) -> String {
        let t = titulo.replacingOccurrences(of: " ", with: "_")
        let codificado = t.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? t
        return "https://\(idioma).wikivoyage.org/wiki/\(codificado)"
    }

    private static func pedirJSON(_ idioma: String, _ parametros: [String: String]) async -> [String: Any]? {
        var c = URLComponents(string: "https://\(idioma).wikivoyage.org/w/api.php")
        var items = [URLQueryItem(name: "format", value: "json")]
        for (k, v) in parametros.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: k, value: v))
        }
        c?.queryItems = items
        guard let url = c?.url else { return nil }
        var peticion = URLRequest(url: url)
        peticion.timeoutInterval = 15
        peticion.setValue("NuestrasEscapadas/1.0 (app privada para iOS)", forHTTPHeaderField: "User-Agent")
        guard let resultado = try? await URLSession.shared.data(for: peticion),
              (resultado.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: resultado.0)) as? [String: Any]
    }

    /// Página del destino (si no existe con ese nombre, la primera que encuentre el buscador).
    static func pagina(idioma: String, titulo: String) async -> Pagina? {
        var nombre = titulo.recortado
        guard !nombre.isEmpty else { return nil }

        for intento in 0..<2 {
            let json = await pedirJSON(idioma, [
                "action": "query", "prop": "extracts|langlinks", "explaintext": "1",
                "exsectionformat": "wiki", "lllang": "en", "redirects": "1", "titles": nombre
            ])
            let paginas = (json?["query"] as? [String: Any])?["pages"] as? [String: Any]
            if let p = paginas?.values.first as? [String: Any], p["missing"] == nil,
               let extracto = p["extract"] as? String, !extracto.isEmpty {
                let tituloReal = (p["title"] as? String) ?? nombre
                let ingles = ((p["langlinks"] as? [[String: Any]])?.first)?["*"] as? String
                let parse = await pedirJSON(idioma, ["action": "parse", "prop": "wikitext", "redirects": "1", "page": tituloReal])
                let wikitext = ((parse?["parse"] as? [String: Any])?["wikitext"] as? [String: Any])?["*"] as? String ?? ""
                return Pagina(titulo: tituloReal, extracto: extracto, wikitext: wikitext, tituloIngles: ingles)
            }
            // No existe con ese nombre: se prueba con lo primero que dé el buscador.
            guard intento == 0 else { break }
            let busqueda = await pedirJSON(idioma, ["action": "query", "list": "search", "srlimit": "1", "srsearch": nombre])
            guard let primero = ((busqueda?["query"] as? [String: Any])?["search"] as? [[String: Any]])?.first,
                  let otro = primero["title"] as? String, otro != nombre else { break }
            nombre = otro
        }
        return nil
    }

    // MARK: Del aeropuerto al centro

    private static func secciones(_ extracto: String) -> [Seccion] {
        var lista = [Seccion(nivel: 1, titulo: "", texto: "")]
        for linea in extracto.components(separatedBy: "\n") {
            let l = linea.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("=="), l.hasSuffix("=="), l.count > 4 {
                let nivel = l.prefix(while: { $0 == "=" }).count
                let titulo = l.trimmingCharacters(in: CharacterSet(charactersIn: "= ")).trimmingCharacters(in: .whitespaces)
                lista.append(Seccion(nivel: nivel, titulo: titulo, texto: ""))
            } else if !l.isEmpty {
                let ultimo = lista.count - 1
                lista[ultimo].texto += (lista[ultimo].texto.isEmpty ? "" : "\n") + l
            }
        }
        return lista
    }

    static func textoAeropuerto(_ extracto: String, idioma: String) -> String {
        let todas = secciones(extracto)
        let titulosLlegar = idioma == "es" ? ["llegar", "como llegar", "cómo llegar"] : ["get in"]
        guard let inicio = todas.firstIndex(where: { $0.nivel == 2 && titulosLlegar.contains($0.titulo.lowercased()) }) else { return "" }
        var bloque = [todas[inicio]]
        var j = inicio + 1
        while j < todas.count && todas[j].nivel > 2 {
            bloque.append(todas[j])
            j += 1
        }

        let pistas = idioma == "es" ? ["avión", "avion", "aeropuerto", "aéreo", "aire"] : ["by plane", "by air", "airport"]
        var partes: [String] = []
        if let k = bloque.indices.dropFirst().first(where: { i in
            let t = bloque[i].titulo.lowercased()
            return pistas.contains(where: { t.contains($0) })
        }) {
            partes.append(bloque[k].texto)
            var h = k + 1
            while h < bloque.count && bloque[h].nivel > bloque[k].nivel {
                partes.append(bloque[h].texto)
                h += 1
            }
        } else if bloque[0].texto.lowercased().contains(idioma == "es" ? "aeropuerto" : "airport") {
            partes.append(bloque[0].texto)
        }
        let texto = partes.filter { !$0.isEmpty }.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(texto.prefix(1500))
    }

    // MARK: Qué ver

    /// Subapartados que son categorías y no sitios.
    private static let categorias: Set<String> = [
        "iglesias", "monumentos", "museos", "palacios", "parques", "teatros", "arquitectura", "barrios",
        "plazas", "jardines", "miradores", "edificios", "galerias", "castillos", "playas", "otros",
        "alrededores", "museums", "churches", "parks", "monuments", "squares", "galleries", "palaces",
        "gardens", "viewpoints", "others", "beaches", "architecture", "sightseeing passes"
    ]

    static func sitios(_ wikitext: String, idioma: String) -> [String] {
        let titulos = idioma == "es" ? ["Ver", "Qué ver", "Que ver", "Lugares de interés"] : ["See"]
        let patronInicio = "(?mi)^==\\s*(?:" + titulos.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")\\s*==\\s*$"
        guard let inicio = wikitext.range(of: patronInicio, options: .regularExpression) else { return [] }
        let resto = wikitext[inicio.upperBound...]
        let fin = resto.range(of: "(?m)^==[^=]", options: .regularExpression)?.lowerBound ?? resto.endIndex
        let seccion = String(resto[..<fin])

        var nombres: [String] = []
        func anadir(_ bruto: String) {
            let n = limpiar(bruto)
            guard n.count >= 3, n.count <= 60, !n.lowercased().contains("http") else { return }
            let clave = HorarioOSM.normalizar(n)
            guard !categorias.contains(clave), !clave.contains(" pass") else { return }    // "Museos", "City Pass"…
            if !nombres.contains(where: { HorarioOSM.normalizar($0) == clave }) { nombres.append(n) }
        }
        // 1) Fichas de sitios: {{see | name=Coliseo | …}} o {{ver | nombre=… }}
        for n in coincidencias("\\|\\s*(?:name|nombre)\\s*=\\s*([^|\\n}]+)", en: seccion) { anadir(n) }
        // 2) Subapartados: === Castillo de Praga ===
        for n in coincidencias("(?m)^===+\\s*([^=\\n]+?)\\s*===+\\s*$", en: seccion) { anadir(n) }
        // 3) Nombres en negrita: '''Puente de Carlos'''
        for n in coincidencias("'''([^'\\n]{3,60})'''", en: seccion) { anadir(n) }
        return Array(nombres.prefix(15))
    }

    private static func coincidencias(_ patron: String, en texto: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: patron) else { return [] }
        let rango = NSRange(texto.startIndex..., in: texto)
        return regex.matches(in: texto, range: rango).compactMap { m in
            guard m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: texto) else { return nil }
            return String(texto[r])
        }
    }

    private static func limpiar(_ bruto: String) -> String {
        var t = bruto
        t = t.replacingOccurrences(of: "\\[\\[[^\\]|]*\\|([^\\]]*)\\]\\]", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\[\\[([^\\]]*)\\]\\]", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\{\\{[^}]*\\}\\}", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "'''", with: "").replacingOccurrences(of: "''", with: "")
        return t.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,:;")))
    }
}

// ============================================================================
// SECCIÓN DE LA PESTAÑA LISTA
// ============================================================================

struct SeccionGuiaDestino: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @ObservedObject private var servicio = ServicioGuias.compartido
    let escapada: Escapada

    @State private var abierta = false

    var body: some View {
        let destino = escapada.destino.recortado
        if !destino.isEmpty {
            let clave = ServicioGuias.clave(destino)
            Section {
                DisclosureGroup(isExpanded: $abierta) {
                    if let g = servicio.guia(destino) {
                        contenido(g)
                    } else if servicio.consultando.contains(clave) {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Buscando la guía en Wikivoyage…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(servicio.sinGuia.contains(clave)
                                 ? "No hay guía de «\(destino)» en Wikivoyage."
                                 : "La guía aún no se ha cargado.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Buscar otra vez") {
                                Task { await servicio.cargar(destino: destino, forzar: true) }
                            }
                            .font(.caption.bold())
                            .buttonStyle(.borderless)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text("📖")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Guía de \(destino)")
                                .font(.subheadline.weight(.semibold))
                            Text("Del aeropuerto al centro y qué ver · Wikivoyage")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            } footer: {
                if abierta {
                    Text("Textos de Wikivoyage (licencia CC BY-SA), escritos por viajeros: pueden no estar al día.")
                }
            }
            .task(id: clave) {
                if !escapada.yaVivida {
                    await servicio.cargar(destino: destino)
                }
            }
            .onChange(of: abierta) { _, ahora in
                if ahora { Task { await servicio.cargar(destino: destino) } }
            }
        }
    }

    @ViewBuilder
    private func contenido(_ g: GuiaDestino) -> some View {
        if !g.llegar.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("✈️ Del aeropuerto al centro\(g.llegarEnIngles ? " (en inglés)" : "")")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(g.llegar)
                    .font(.caption)
                    .lineLimit(14)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)
        }

        if !g.ver.isEmpty {
            Text("📍 Qué ver\(g.verEnIngles ? " (nombres en inglés)" : "") · toca + para pasarlo a vuestras ideas")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(g.ver, id: \.self) { sitio in
                let yaEsta = estaEnIdeas(sitio)
                HStack {
                    Text(sitio)
                        .font(.subheadline)
                    Spacer()
                    Button {
                        if !yaEsta { anadirIdea(sitio) }
                    } label: {
                        Image(systemName: yaEsta ? "checkmark.circle.fill" : "plus.circle")
                            .foregroundStyle(yaEsta ? Color.green : Color.accentColor)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        if let url = URL(string: g.url) {
            Link(destination: url) {
                Label("Abrir la guía completa en Wikivoyage", systemImage: "safari")
                    .font(.subheadline)
            }
        }
    }

    private func estaEnIdeas(_ sitio: String) -> Bool {
        let s = HorarioOSM.normalizar(sitio)
        return almacen.ideasDe(escapada.id).contains { HorarioOSM.normalizar($0.texto).contains(s) }
    }

    private func anadirIdea(_ sitio: String) {
        var idea = Idea()
        idea.escapadaId = escapada.id
        idea.texto = "📍 \(sitio)"
        idea.autorId = sesion.miId
        almacen.guardar(idea, en: .ideas)
    }
}
