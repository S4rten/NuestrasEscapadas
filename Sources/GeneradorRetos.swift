import SwiftUI

// ============================================================================
// RETOS SUGERIDOS: cada vez salen 10 distintos.
//  · Sitios reales cerca del destino, sacados de Wikipedia (cambian con cada viaje).
//  · Retos inventados al azar combinando piezas (más de mil combinaciones).
// Se recuerdan los últimos sugeridos en este iPhone para no repetirlos pronto.
// ============================================================================

enum GeneradorRetos {
    private static let claveHistorial = "escapadas_retos_sugeridos_v1"
    private static let maximoHistorial = 400

    // MARK: Piezas para inventar retos

    private static let cosas: [String] = [
        "una puerta de colores", "un gato callejero", "un perro con mucho estilo", "una bicicleta aparcada",
        "un balcón lleno de flores", "una fuente", "el transporte típico del sitio", "un cartel que no entendáis",
        "la ventana más bonita del día", "un reloj en la calle", "una escalera curiosa", "un puente",
        "un grafiti", "una estatua", "un músico callejero", "un puesto del mercado", "el plato más típico",
        "el mejor postre del viaje", "una tienda antigua", "un buzón", "una farola bonita", "los tejados",
        "un árbol enorme", "una barca", "un campanario", "una plaza con vida", "un coche antiguo",
        "un escaparate original", "un helado", "vuestro café de la mañana", "una calle estrechísima",
        "un banco para descansar", "un letrero luminoso", "una señal de tráfico rara", "un mosaico",
        "unas baldosas bonitas", "una nube con forma de algo", "una pintada con mensaje", "una cúpula",
        "un mirador", "una persiana pintada", "un tranvía", "una paloma posando", "un detalle diminuto que nadie mira"
    ]

    private static let maneras: [String] = [
        "desde abajo", "reflejada en un charco o un cristal", "con los dos en la foto", "en blanco y negro",
        "sin que se vea el cielo", "desde lo más alto que podáis", "enmarcada con vuestras manos",
        "muy de cerca, que no se sepa qué es", "con algo rojo al lado", "al atardecer", "de noche",
        "sin usar el zoom", "torcida a propósito", "con vuestras sombras", "como si fuera una postal",
        "desde el suelo", "a través de una ventana", "con algo borroso delante", "a contraluz",
        "en menos de 30 segundos desde que la veáis", "con un desconocido al lado", "imitando su pose",
        "en vertical y en horizontal (y elegid la mejor)", "con el móvil boca abajo"
    ]

    private static let poses: [String] = [
        "saltando a la vez", "con cara de sorpresa", "imitando una estatua", "con la peor cara posible",
        "dándoos un beso", "con gafas de sol los dos", "riéndoos a carcajadas", "de espaldas",
        "haciendo un corazón con las manos", "señalando algo que no sale en la foto", "con la boca llena",
        "sin mirar a la cámara", "con un gorro o un sombrero", "en plan foto de pasaporte", "abrazados",
        "chocando los cinco", "como en la portada de un disco", "con cara de turistas perdidos",
        "con un recuerdo recién comprado", "bailando"
    ]

    private static let sitios: [String] = [
        "en una plaza", "junto al agua", "en un mirador", "delante de una puerta enorme",
        "en el transporte público", "en un mercado", "con un monumento al fondo", "en una calle estrecha",
        "delante de vuestro alojamiento", "en lo más alto que subáis", "en una terraza", "en una escalera",
        "debajo de un árbol", "en un puente", "en la entrada de un museo", "junto a una fuente",
        "en una tienda de recuerdos", "con las mejores vistas del día", "en un parque", "en una estación"
    ]

    private static let colores: [String] = ["rojo", "amarillo", "verde", "azul", "naranja", "morado", "rosa", "blanco", "dorado"]

    private static let letras = Array("ABCDEFGIJLMNOPRSTV").map { String($0) }

    private static let sueltos: [String] = [
        "🍽️ Pedid algo de la carta sin saber qué es y fotografiadlo",
        "🗺️ Perdeos 15 minutos sin mapa y foto de donde acabéis",
        "🎨 Foto de los dos que parezca un cuadro",
        "🪞 Selfie en el espejo más bonito que encontréis",
        "🌅 Foto del amanecer (¡madrugón incluido!)",
        "👣 Foto de vuestros pies en tres suelos distintos",
        "🧭 Foto de algo que no exista en vuestra ciudad",
        "🚶 Foto de la calle más bonita según los dos",
        "🍷 Brindis con la bebida típica del sitio",
        "📮 Foto con algo del color de vuestra ropa",
        "🗣️ Aprended a decir «gracias» en el idioma local y grabad a alguien respondiendo",
        "🎭 Recread una escena de película en un sitio del viaje",
        "🕰️ Foto exactamente a las 12:00 estéis donde estéis",
        "🛍️ Foto del recuerdo más feo de la tienda",
        "🐾 Foto con el primer animal que veáis hoy",
        "🌧️ Foto bonita aunque haga mal tiempo",
        "🎶 Foto de alguien tocando música",
        "🧁 Foto del dulce más raro del viaje",
        "🚪 Foto de la puerta más grande que encontréis",
        "🌉 Foto de los dos con el sitio más alto de la ciudad al fondo"
    ] + RetosSugeridos.lista

    private static let plantillasLugar: [String] = [
        "🏛️ Selfie delante de «%@»",
        "📸 La foto más original de «%@»",
        "🤳 Imitad una pose con «%@» al fondo",
        "🗺️ Llegad hasta «%@» y haceos una foto",
        "🌅 Foto de «%@» con buena luz"
    ]

    // MARK: Generar

    /// Retos nuevos para esta escapada: sin repetir los ya añadidos ni los sugeridos hace poco.
    static func sugerir(cuantos: Int = 10, escapada: Escapada, yaAnadidos: [String]) async -> [String] {
        let historial = Set(UserDefaults.standard.stringArray(forKey: claveHistorial) ?? [])
        let anadidos = Set(yaAnadidos.map { $0.lowercased() })
        var elegidos: [String] = []
        var claves: Set<String> = []

        func aceptar(_ reto: String) {
            let clave = reto.lowercased()
            guard !historial.contains(clave), !anadidos.contains(clave), !claves.contains(clave) else { return }
            elegidos.append(reto)
            claves.insert(clave)
        }

        // 1) Hasta 4 sitios reales cerca del destino.
        if let lat = escapada.latitud, let lon = escapada.longitud {
            let lugares = await lugaresCercanos(lat: lat, lon: lon, destino: escapada.destino).shuffled()
            for lugar in lugares {
                if elegidos.count >= 4 { break }
                aceptar(retoDeLugar(lugar))
            }
        }

        // 2) El resto, inventados al azar.
        var intentos = 0
        while elegidos.count < cuantos && intentos < 1000 {
            intentos += 1
            aceptar(retoInventado())
        }
        // Por si el historial ya lo tiene casi todo: se permite repetir los más antiguos.
        if elegidos.count < cuantos {
            UserDefaults.standard.removeObject(forKey: claveHistorial)
            while elegidos.count < cuantos && intentos < 2000 {
                intentos += 1
                let reto = retoInventado()
                let clave = reto.lowercased()
                if !anadidos.contains(clave) && !claves.contains(clave) {
                    elegidos.append(reto)
                    claves.insert(clave)
                }
            }
        }

        apuntarEnHistorial(elegidos)
        return elegidos.shuffled()
    }

    private static func al(_ lista: [String]) -> String {
        lista.randomElement() ?? ""
    }

    private static func retoInventado() -> String {
        let tirada = Int.random(in: 0..<100)
        if tirada < 40 {
            return "📸 Foto de \(al(cosas)) \(al(maneras))"
        } else if tirada < 75 {
            return "🤳 Selfie \(al(poses)) \(al(sitios))"
        } else if tirada < 83 {
            return "🎨 Encontrad \(Int.random(in: 3...5)) cosas de color \(al(colores)) y foto a cada una"
        } else if tirada < 90 {
            return "🔤 Foto de algo que empiece por la letra \(al(letras))"
        } else {
            return al(sueltos)
        }
    }

    private static func retoDeLugar(_ lugar: String) -> String {
        al(plantillasLugar).replacingOccurrences(of: "%@", with: lugar)
    }

    private static func apuntarEnHistorial(_ nuevos: [String]) {
        var lista = UserDefaults.standard.stringArray(forKey: claveHistorial) ?? []
        lista.append(contentsOf: nuevos.map { $0.lowercased() })
        if lista.count > maximoHistorial {
            lista.removeFirst(lista.count - maximoHistorial)
        }
        UserDefaults.standard.set(lista, forKey: claveHistorial)
    }

    // MARK: Sitios cercanos (Wikipedia, sin clave)

    private static func lugaresCercanos(lat: Double, lon: Double, destino: String) async -> [String] {
        var c = URLComponents(string: "https://es.wikipedia.org/w/api.php")
        c?.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "list", value: "geosearch"),
            URLQueryItem(name: "gscoord", value: "\(lat)|\(lon)"),
            URLQueryItem(name: "gsradius", value: "10000"),
            URLQueryItem(name: "gslimit", value: "100"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = c?.url else { return [] }
        var peticion = URLRequest(url: url)
        peticion.timeoutInterval = 8
        peticion.setValue("NuestrasEscapadas/1.0 (app privada para iOS)", forHTTPHeaderField: "User-Agent")
        guard let respuesta = try? await URLSession.shared.data(for: peticion),
              let json = (try? JSONSerialization.jsonObject(with: respuesta.0)) as? [String: Any],
              let consulta = json["query"] as? [String: Any],
              let lista = consulta["geosearch"] as? [[String: Any]] else { return [] }

        // Fuera la propia ciudad y lo que no tiene gracia para una foto (carreteras, distritos…).
        let ciudad = destino.recortado.lowercased()
        let descartar = ["anexo:", "autovía", "autopista", "carretera", "línea ", "distrito", "municipio", "provincia"]
        return lista
            .compactMap { $0["title"] as? String }
            .filter { titulo in
                let t = titulo.lowercased()
                guard titulo.count >= 4, titulo.count <= 45, t != ciudad else { return false }
                return !descartar.contains(where: { t.contains($0) })
            }
    }
}

// ============================================================================
// HOJA CON LOS 10 RETOS SUGERIDOS
// ============================================================================

struct SugerenciasRetosView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @Environment(\.dismiss) private var dismiss

    let escapada: Escapada

    @State private var sugerencias: [String] = []
    @State private var cargando = false

    var body: some View {
        let actuales = almacen.retosDe(escapada.id).map { $0.texto }

        NavigationStack {
            List {
                if cargando && sugerencias.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Pensando retos…")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(sugerencias, id: \.self) { s in
                        let anadido = actuales.contains(s)
                        Button {
                            if !anadido { anadir(s) }
                        } label: {
                            HStack(spacing: 10) {
                                Text(s)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                                Image(systemName: anadido ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(anadido ? Color.green : Color.accentColor)
                            }
                        }
                    }
                } footer: {
                    if !sugerencias.isEmpty {
                        Text("Toca un reto para añadirlo. Cada vez salen otros distintos; los de sitios reales son de cerca de vuestro destino.")
                    }
                }

                Section {
                    Button {
                        for s in sugerencias where !actuales.contains(s) { anadir(s) }
                    } label: {
                        Label("Añadir todos", systemImage: "sparkles")
                    }
                    .disabled(sugerencias.isEmpty || sugerencias.allSatisfy { actuales.contains($0) })

                    Button {
                        Task { await generar() }
                    } label: {
                        HStack {
                            Label("Otros 10 distintos", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if cargando && !sugerencias.isEmpty { ProgressView() }
                        }
                    }
                    .disabled(cargando)
                }
            }
            .navigationTitle("Retos sugeridos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .task {
                if sugerencias.isEmpty { await generar() }
            }
        }
    }

    private func generar() async {
        cargando = true
        let actuales = almacen.retosDe(escapada.id).map { $0.texto }
        sugerencias = await GeneradorRetos.sugerir(escapada: escapada, yaAnadidos: actuales)
        cargando = false
    }

    private func anadir(_ texto: String) {
        guard !almacen.retosDe(escapada.id).contains(where: { $0.texto == texto }) else { return }
        var reto = Reto()
        reto.escapadaId = escapada.id
        reto.texto = texto
        reto.creadoPorId = sesion.miId
        reto.creadoEn = Date()
        almacen.guardar(reto, en: .retos)
    }
}
