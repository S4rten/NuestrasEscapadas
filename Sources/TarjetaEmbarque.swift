import UIKit
import Vision

// ============================================================================
// TARJETA DE EMBARQUE: el código (PDF417, Aztec o QR) de las tarjetas de
// embarque sigue el estándar IATA "BCBP" y lleva el localizador, el vuelo, los
// aeropuertos, el día y el asiento. Se lee en el propio iPhone, sin internet.
// ============================================================================

struct TarjetaEmbarque: Equatable {
    var pasajero: String = ""               // "SANCHEZ/ERIC"
    var localizador: String = ""
    var origen: String = ""
    var destino: String = ""
    var aerolinea: String = ""              // "IB"
    var numero: String = ""                 // "3140"
    var diaDelAno: Int = 0                  // día juliano (1-366)
    var asiento: String = ""                // "14C"

    var numeroVuelo: String { aerolinea + numero }

    /// "Eric" a partir de "SANCHEZ/ERIC MR".
    var nombrePila: String {
        let partes = pasajero.split(separator: "/")
        guard partes.count >= 2 else { return pasajero.capitalized }
        var nombre = String(partes[1]).trimmingCharacters(in: .whitespaces)
        for tratamiento in [" MR", " MRS", " MS", " MISS", " MSTR", " DR"] where nombre.hasSuffix(tratamiento) {
            nombre = String(nombre.dropLast(tratamiento.count))
        }
        let primero = nombre.split(separator: " ").first.map(String.init) ?? nombre
        return primero.capitalized
    }

    /// El día del vuelo (el año no va en el código: se toma el más cercano a `referencia`).
    func fecha(cercaDe referencia: Date) -> Date? {
        guard (1...366).contains(diaDelAno) else { return nil }
        let cal = Calendar.current
        let ano = cal.component(.year, from: referencia)
        var mejor: Date? = nil
        for a in [ano - 1, ano, ano + 1] {
            guard let inicio = cal.date(from: DateComponents(year: a, month: 1, day: 1)),
                  let dia = cal.date(byAdding: .day, value: diaDelAno - 1, to: inicio) else { continue }
            if let m = mejor {
                if abs(dia.timeIntervalSince(referencia)) < abs(m.timeIntervalSince(referencia)) { mejor = dia }
            } else {
                mejor = dia
            }
        }
        return mejor
    }
}

enum LectorTarjetaEmbarque {
    /// Busca en la imagen un código de tarjeta de embarque y lo interpreta.
    static func leer(_ imagen: UIImage) async -> TarjetaEmbarque? {
        for texto in await codigos(imagen) {
            if let t = interpretar(texto) { return t }
        }
        return nil
    }

    private static func codigos(_ imagen: UIImage) async -> [String] {
        guard let cg = imagen.cgImage else { return [] }
        let orientacion = CGImagePropertyOrientation(imagen.imageOrientation)
        return await withCheckedContinuation { continuacion in
            DispatchQueue.global(qos: .userInitiated).async {
                let peticion = VNDetectBarcodesRequest()
                peticion.symbologies = [.pdf417, .aztec, .qr, .dataMatrix]
                let manejador = VNImageRequestHandler(cgImage: cg, orientation: orientacion, options: [:])
                try? manejador.perform([peticion])
                let textos = (peticion.results ?? []).compactMap { $0.payloadStringValue }
                continuacion.resume(returning: textos)
            }
        }
    }

    /// Campos fijos del estándar BCBP (primer tramo):
    /// M1 · nombre (20) · E · localizador (7) · origen (3) · destino (3) · aerolínea (3) ·
    /// nº de vuelo (5) · día juliano (3) · clase (1) · asiento (4) · …
    static func interpretar(_ bruto: String) -> TarjetaEmbarque? {
        let t = Array(bruto)
        guard t.count >= 52, t[0] == "M" else { return nil }

        func trozo(_ inicio: Int, _ largo: Int) -> String {
            guard inicio < t.count else { return "" }
            let fin = min(inicio + largo, t.count)
            return String(t[inicio..<fin]).trimmingCharacters(in: .whitespaces)
        }

        var tarjeta = TarjetaEmbarque()
        tarjeta.pasajero = trozo(2, 20)
        tarjeta.localizador = trozo(23, 7)
        tarjeta.origen = trozo(30, 3).uppercased()
        tarjeta.destino = trozo(33, 3).uppercased()
        tarjeta.aerolinea = trozo(36, 3).uppercased()
        var numero = trozo(39, 5).filter { $0.isNumber || $0.isLetter }
        while numero.count > 1 && numero.hasPrefix("0") { numero.removeFirst() }
        tarjeta.numero = numero
        tarjeta.diaDelAno = Int(trozo(44, 3)) ?? 0
        var asiento = trozo(48, 4)
        while asiento.count > 1 && asiento.hasPrefix("0") { asiento.removeFirst() }
        tarjeta.asiento = asiento

        let letras = CharacterSet.uppercaseLetters
        let aeropuertosBien = [tarjeta.origen, tarjeta.destino].allSatisfy {
            $0.count == 3 && $0.unicodeScalars.allSatisfy { letras.contains($0) }
        }
        guard aeropuertosBien, !tarjeta.aerolinea.isEmpty, !tarjeta.numero.isEmpty,
              (1...366).contains(tarjeta.diaDelAno) else { return nil }
        return tarjeta
    }
}

extension Almacen {
    /// Completa el vuelo con lo leído de una o varias tarjetas de embarque (por ejemplo, la de
    /// cada uno). Solo rellena lo que falta y avisa si algo no cuadra. Devuelve el texto para enseñar.
    func aplicarTarjetas(_ tarjetas: [TarjetaEmbarque], aVuelo original: Vuelo) -> String {
        guard let primera = tarjetas.first else { return "" }
        var v = original
        var campos: [String: Any] = [:]
        var avisos: [String] = []
        func avisar(_ texto: String) {
            if !avisos.contains(texto) { avisos.append(texto) }
        }

        for t in tarjetas {
            let numeroActual = v.numeroVuelo.uppercased().filter { $0.isLetter || $0.isNumber }
            if numeroActual.isEmpty {
                v.numeroVuelo = t.numeroVuelo
                campos["numeroVuelo"] = t.numeroVuelo
            } else if numeroActual != t.numeroVuelo && !numeroActual.hasSuffix(t.numero) {
                avisar("la tarjeta es del vuelo \(t.numeroVuelo), no del \(numeroActual)")
            }
            if v.localizador.recortado.isEmpty && !t.localizador.isEmpty {
                v.localizador = t.localizador
                campos["localizador"] = t.localizador
            }
            if v.origen.recortado.isEmpty {
                v.origen = t.origen
                campos["origen"] = t.origen
            } else if v.origen.uppercased() != t.origen {
                avisar("sale de \(t.origen), no de \(v.origen.uppercased())")
            }
            if v.destino.recortado.isEmpty {
                v.destino = t.destino
                campos["destino"] = t.destino
            } else if v.destino.uppercased() != t.destino {
                avisar("va a \(t.destino), no a \(v.destino.uppercased())")
            }
            if let dia = t.fecha(cercaDe: v.fechaHoraSalida), !v.saleElDia(dia) {
                avisar("es del \(dia.formatted(date: .abbreviated, time: .omitted))")
            }
            // Asientos de los dos: "14C (Eric) · 14D (Ana)".
            if !t.asiento.isEmpty && !v.asiento.uppercased().contains(t.asiento.uppercased()) {
                let nuevo = t.nombrePila.isEmpty ? t.asiento : "\(t.asiento) (\(t.nombrePila))"
                v.asiento = v.asiento.recortado.isEmpty ? nuevo : "\(v.asiento.recortado) · \(nuevo)"
                campos["asiento"] = v.asiento
            }
        }

        if !campos.isEmpty {
            actualizar(original.id, en: .vuelos, campos: campos)
        }

        var texto: String
        if tarjetas.count == 1 {
            texto = "🎫 Tarjeta leída: \(primera.numeroVuelo) · \(primera.origen) → \(primera.destino)"
            if !primera.asiento.isEmpty { texto += " · asiento \(primera.asiento)" }
            if !primera.nombrePila.isEmpty { texto += " (\(primera.nombrePila))" }
            texto += "."
        } else {
            texto = "🎫 \(tarjetas.count) tarjetas leídas (\(primera.numeroVuelo) · \(primera.origen) → \(primera.destino))."
        }
        if !avisos.isEmpty {
            texto += " ⚠️ Ojo: " + avisos.joined(separator: "; ") + "."
        } else if !campos.isEmpty {
            texto += " Datos del vuelo completados."
        }
        return texto
    }
}
