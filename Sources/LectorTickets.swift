import SwiftUI
import UIKit
import PhotosUI
import Vision
import ImageIO

// ============================================================================
// ESCANEAR TICKET: haces una foto al ticket y se rellenan solos el importe,
// el comercio y la fecha. Se lee en el propio iPhone (Vision), sin internet,
// y la foto no se guarda en ningún sitio.
// ============================================================================

struct TicketLeido {
    var importe: Double? = nil
    var comercio: String? = nil
    var fecha: Date? = nil
    var categoria: String? = nil

    var vacio: Bool { importe == nil && comercio == nil }
}

enum LectorTickets {
    /// Un trozo de texto reconocido con su posición (y: 0 abajo, 1 arriba).
    private struct Trozo {
        let texto: String
        let y: CGFloat
    }

    static func leer(_ imagen: UIImage) async -> TicketLeido {
        let trozos = await reconocer(imagen)
        return interpretar(trozos)
    }

    // MARK: Reconocimiento de texto

    private static func reconocer(_ imagen: UIImage) async -> [Trozo] {
        guard let cg = imagen.cgImage else { return [] }
        let orientacion = CGImagePropertyOrientation(imagen.imageOrientation)
        return await withCheckedContinuation { continuacion in
            DispatchQueue.global(qos: .userInitiated).async {
                let peticion = VNRecognizeTextRequest()
                peticion.recognitionLevel = .accurate
                peticion.usesLanguageCorrection = false
                peticion.recognitionLanguages = ["es-ES", "en-US", "fr-FR", "it-IT", "de-DE", "pt-PT"]
                let manejador = VNImageRequestHandler(cgImage: cg, orientation: orientacion, options: [:])
                try? manejador.perform([peticion])
                let resultado = (peticion.results ?? []).compactMap { obs -> Trozo? in
                    guard let texto = obs.topCandidates(1).first?.string else { return nil }
                    return Trozo(texto: texto, y: obs.boundingBox.midY)
                }
                continuacion.resume(returning: resultado)
            }
        }
    }

    // MARK: Interpretación

    private static let palabrasTotal = ["total", "importe", "a pagar", "totale", "summe", "gesamt", "amount", "montant", "à payer", "tarjeta", "card"]
    private static let palabrasExcluir = ["subtotal", "sub-total", "sub total", "iva", "i.v.a", "base", "tax", "vat", "cambio", "entregado", "efectivo", "change", "cash", "descuento", "propina"]

    private static func interpretar(_ trozos: [Trozo]) -> TicketLeido {
        var t = TicketLeido()
        guard !trozos.isEmpty else { return t }
        let deArribaAAbajo = trozos.sorted { $0.y > $1.y }

        // 1) Importe: la cifra en la misma línea (o justo debajo) que "TOTAL".
        var candidatos: [Double] = []
        for trozo in deArribaAAbajo {
            let minus = trozo.texto.lowercased()
            guard palabrasTotal.contains(where: { minus.contains($0) }),
                  !palabrasExcluir.contains(where: { minus.contains($0) }) else { continue }
            let cercanos = deArribaAAbajo.filter { abs($0.y - trozo.y) < 0.012 || ($0.y < trozo.y && trozo.y - $0.y < 0.03) }
            for c in [trozo] + cercanos {
                candidatos.append(contentsOf: importes(en: c.texto))
            }
        }
        if let mayor = candidatos.max(), mayor > 0 {
            t.importe = mayor
        } else {
            // Sin "TOTAL" reconocible: la cifra más alta del ticket (con tope razonable).
            t.importe = deArribaAAbajo.flatMap { importes(en: $0.texto) }.filter { $0 < 20_000 }.max()
        }

        // 2) Comercio: la primera línea de arriba con letras que no sea un dato fiscal.
        let ignorar = ["ticket", "factura", "simplificada", "cif", "nif", "n.i.f", "c.i.f", "tel", "www", "http", "@", "fecha", "hora", "mesa", "nº", "copia"]
        for trozo in deArribaAAbajo.prefix(8) {
            let limpio = trozo.texto.recortado
            let minus = limpio.lowercased()
            let letras = limpio.filter { $0.isLetter }.count
            if letras >= 3, letras * 2 >= limpio.count, !ignorar.contains(where: { minus.contains($0) }) {
                t.comercio = limpio.capitalized
                break
            }
        }

        // 3) Fecha (dd/mm/aa o dd/mm/aaaa).
        for trozo in deArribaAAbajo {
            if let f = fecha(en: trozo.texto) {
                t.fecha = f
                break
            }
        }

        // 4) Categoría orientativa por el nombre del comercio o el texto del ticket.
        let todo = deArribaAAbajo.map { $0.texto.lowercased() }.joined(separator: " ")
        t.categoria = categoria(para: (t.comercio ?? "").lowercased() + " " + todo)
        return t
    }

    /// Cifras con dos decimales: "12,50", "1.234,56", "45.90", "€ 7,00".
    private static func importes(en texto: String) -> [Double] {
        let patron = #"(\d{1,3}(?:[.,\s]\d{3})*|\d+)[.,](\d{2})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: patron) else { return [] }
        let rango = NSRange(texto.startIndex..., in: texto)
        return regex.matches(in: texto, range: rango).compactMap { m in
            guard let rEnteros = Range(m.range(at: 1), in: texto),
                  let rDecimales = Range(m.range(at: 2), in: texto) else { return nil }
            let enteros = texto[rEnteros].filter { $0.isNumber }
            return Double("\(enteros).\(texto[rDecimales])")
        }
    }

    private static func fecha(en texto: String) -> Date? {
        let patron = #"(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})"#
        guard let regex = try? NSRegularExpression(pattern: patron),
              let m = regex.firstMatch(in: texto, range: NSRange(texto.startIndex..., in: texto)),
              let rd = Range(m.range(at: 1), in: texto),
              let rm = Range(m.range(at: 2), in: texto),
              let ra = Range(m.range(at: 3), in: texto),
              let dia = Int(texto[rd]), let mes = Int(texto[rm]), var ano = Int(texto[ra]) else { return nil }
        if ano < 100 { ano += 2000 }
        guard (1...31).contains(dia), (1...12).contains(mes), (2000...2100).contains(ano) else { return nil }
        return Calendar.current.date(from: DateComponents(year: ano, month: mes, day: dia, hour: 12))
    }

    private static func categoria(para texto: String) -> String? {
        let reglas: [(CategoriaGasto, [String])] = [
            (.transporte, ["taxi", "uber", "cabify", "bolt", "metro", "bus", "renfe", "parking", "aparcamiento", "gasolina", "gasolinera", "repsol", "cepsa", "peaje", "combustible", "fuel"]),
            (.alojamiento, ["hotel", "hostal", "apartamento", "airbnb", "booking"]),
            (.entradas, ["museo", "museum", "entrada", "admission", "ticket de entrada", "visita", "tour"]),
            (.comida, ["restaurante", "restaurant", "bar", "cafe", "café", "cafetería", "pizzeria", "trattoria", "mesa", "cubierto", "bebida", "menu", "menú", "supermercado", "mercadona", "carrefour", "lidl", "panadería"])
        ]
        for (cat, palabras) in reglas where palabras.contains(where: { texto.contains($0) }) {
            return cat.rawValue
        }
        return nil
    }
}

extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// ============================================================================
// SECCIÓN DEL FORMULARIO DE GASTO: botones para escanear y resultado.
// ============================================================================

struct SeccionEscanearTicket: View {
    let alLeer: (TicketLeido) -> Void

    @State private var camara = false
    @State private var galeria = false
    @State private var foto: PhotosPickerItem? = nil
    @State private var leyendo = false
    @State private var mensaje = ""

    var body: some View {
        // Cada botón en su propia fila: con los dos en la misma fila, al tocar
        // "galería" la lista podía disparar el otro botón y no abrirse nunca.
        Section {
            Button {
                camara = true
            } label: {
                Label("Escanear ticket con la cámara", systemImage: "doc.text.viewfinder")
            }
            .disabled(leyendo || !UIImagePickerController.isSourceTypeAvailable(.camera))
            .fullScreenCover(isPresented: $camara) {
                SelectorCamara(
                    alHacerFoto: { imagen in
                        camara = false
                        procesar(imagen)
                    },
                    alCancelar: { camara = false },
                    frontal: false
                )
                .ignoresSafeArea()
            }

            Button {
                galeria = true
            } label: {
                Label("Elegir la foto del ticket de la galería", systemImage: "photo.on.rectangle")
            }
            .disabled(leyendo)
            .photosPicker(isPresented: $galeria, selection: $foto, matching: .images)
            .onChange(of: foto) { _, item in
                guard let item = item else { return }
                leyendo = true
                mensaje = "Abriendo la foto…"
                Task {
                    let imagen = await cargarImagen(item)
                    foto = nil
                    if let imagen = imagen {
                        procesar(imagen)
                    } else {
                        leyendo = false
                        mensaje = "No se pudo abrir esa foto. Si está en iCloud, espera a que se descargue y prueba otra vez."
                    }
                }
            }

            if leyendo {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Un momento…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(mensaje.isEmpty ? "Haz una foto al ticket (o elige una de la galería) y se rellenan solos el importe, el comercio y la fecha. La foto no se guarda." : mensaje)
        }
    }

    /// Carga la foto elegida y la reduce si es enorme (así se lee más rápido y sin agotar memoria).
    private func cargarImagen(_ item: PhotosPickerItem) async -> UIImage? {
        guard let datos = try? await item.loadTransferable(type: Data.self),
              let imagen = UIImage(data: datos) else { return nil }
        let lado = max(imagen.size.width, imagen.size.height)
        guard lado > 3000 else { return imagen }
        let escala = 3000 / lado
        let nuevo = CGSize(width: floor(imagen.size.width * escala), height: floor(imagen.size.height * escala))
        let formato = UIGraphicsImageRendererFormat.default()
        formato.scale = 1
        return UIGraphicsImageRenderer(size: nuevo, format: formato).image { _ in
            imagen.draw(in: CGRect(origin: .zero, size: nuevo))
        }
    }

    private func procesar(_ imagen: UIImage) {
        leyendo = true
        mensaje = "Leyendo el ticket…"
        Task {
            let t = await LectorTickets.leer(imagen)
            leyendo = false
            if t.vacio {
                mensaje = "No se ha podido leer. Prueba con más luz y el ticket bien estirado, o escríbelo a mano."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else {
                var partes: [String] = []
                if let i = t.importe { partes.append(i.formatted(.number.precision(.fractionLength(2)))) }
                if let c = t.comercio { partes.append(c) }
                mensaje = "Leído: \(partes.joined(separator: " · ")). Revisa que esté bien antes de guardar."
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                alLeer(t)
            }
        }
    }
}
