import SwiftUI

// ============================================================================
// AMANECER Y ATARDECER: se calculan en el propio iPhone (fórmula astronómica
// estándar, error de 1-2 minutos), así salen para cualquier día del viaje,
// aunque falten meses o no haya conexión. Se enseñan en la hora del destino.
// ============================================================================

enum Sol {
    /// Salida y puesta del sol (instantes exactos) un día concreto. nil si ese día
    /// el sol no sale o no se pone (cerca de los polos).
    static func salidaYPuesta(ano: Int, mes: Int, dia: Int, lat: Double, lon: Double) -> (salida: Date, puesta: Date)? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        guard let medianoche = utc.date(from: DateComponents(year: ano, month: mes, day: dia)) else { return nil }

        let rad = Double.pi / 180
        let diaJuliano = medianoche.timeIntervalSince1970 / 86400 + 2440587.5
        let n = (diaJuliano - 2451545.0 + 0.0008).rounded(.up)
        let mediodiaMedio = n - lon / 360
        let anomalia = (357.5291 + 0.98560028 * mediodiaMedio).truncatingRemainder(dividingBy: 360)
        let m = anomalia * rad
        let centro = 1.9148 * sin(m) + 0.02 * sin(2 * m) + 0.0003 * sin(3 * m)
        let longitud = (anomalia + centro + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let l = longitud * rad
        let transito = 2451545.0 + mediodiaMedio + 0.0053 * sin(m) - 0.0069 * sin(2 * l)
        let senoDeclinacion = sin(l) * sin(23.4397 * rad)
        let cosenoDeclinacion = cos(asin(senoDeclinacion))
        let phi = lat * rad
        let numerador = sin(-0.833 * rad) - sin(phi) * senoDeclinacion
        let cosenoAngulo = numerador / (cos(phi) * cosenoDeclinacion)
        guard cosenoAngulo >= -1, cosenoAngulo <= 1 else { return nil }
        let angulo = acos(cosenoAngulo) / rad

        func fecha(_ juliano: Double) -> Date {
            Date(timeIntervalSince1970: (juliano - 2440587.5) * 86400)
        }
        return (fecha(transito - angulo / 360), fecha(transito + angulo / 360))
    }

    /// Para un día del viaje (fecha del calendario del iPhone) en el destino.
    static func delDia(_ fecha: Date, lat: Double, lon: Double) -> (salida: Date, puesta: Date)? {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: fecha)
        guard let a = c.year, let m = c.month, let d = c.day else { return nil }
        return salidaYPuesta(ano: a, mes: m, dia: d, lat: lat, lon: lon)
    }
}

/// Fila del Plan: "🌅 Amanecer 07:41 · 🌇 Atardecer 16:05 · 8 h 24 min de luz".
struct FilaSolDia: View {
    @ObservedObject private var zonas = ZonasDestino.compartido
    let escapada: Escapada
    let dia: Int

    var body: some View {
        Group {
            if let lat = escapada.latitud, let lon = escapada.longitud,
               let sol = Sol.delDia(escapada.fechaParaDia(dia), lat: lat, lon: lon) {
                let zona = zonas.zona(lat: lat, lon: lon) ?? .current
                let luz = Int(sol.puesta.timeIntervalSince(sol.salida) / 60)
                HStack(spacing: 10) {
                    Text("🌅 \(sol.salida.hora(en: zona))")
                    Text("🌇 \(sol.puesta.hora(en: zona))")
                    Spacer()
                    Text("\(textoDuracion(luz)) de luz")
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.medium))
            }
        }
        .task(id: "\(escapada.latitud ?? 0),\(escapada.longitud ?? 0)") {
            if let lat = escapada.latitud, let lon = escapada.longitud {
                await zonas.averiguar(lat: lat, lon: lon)
            }
        }
    }
}

extension Escapada {
    /// "🌇 Hoy el atardecer es a las 16:05" (durante el viaje) o el del primer día (antes).
    @MainActor
    func textoAtardecer(amanecer: Bool = false) -> String? {
        guard let lat = latitud, let lon = longitud else { return nil }
        let dia = diaDeHoy ?? 1
        guard let sol = Sol.delDia(fechaParaDia(dia), lat: lat, lon: lon) else { return nil }
        let zona = ZonasDestino.compartido.zona(lat: lat, lon: lon) ?? .current
        let cuando = diaDeHoy != nil ? "Hoy" : "El día 1"
        return amanecer
            ? "🌅 \(cuando) amanece a las \(sol.salida.hora(en: zona))"
            : "🌇 \(cuando) el atardecer es a las \(sol.puesta.hora(en: zona))"
    }
}
