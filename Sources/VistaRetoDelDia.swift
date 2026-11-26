import SwiftUI

// ============================================================================
// RETO SORPRESA DEL DÍA: cada día del viaje se desbloquea un reto que no se
// ve hasta ese día. Se elige con una semilla fija (viaje + día), así los dos
// iPhones ven el mismo reto sin guardar nada. Al aceptarlo pasa a la lista.
// ============================================================================

enum RetosSorpresa {
    static let lista = [
        "Selfie con el plato más raro que encontréis",
        "Foto de los dos con un desconocido haciendo el signo de la paz",
        "Recread una postal típica del sitio",
        "Selfie con un animal (¡de lejos si hace falta!)",
        "Foto de vuestras sombras juntas",
        "Foto de algo de vuestro color favorito",
        "Selfie con la peor cara posible",
        "Foto de la puerta más bonita que veáis",
        "Foto del mejor postre del día",
        "Selfie imitando a un cuadro o una estatua",
        "Foto de vuestros pies en un sitio especial",
        "Foto con un cartel en el idioma local",
        "Selfie en lo más alto que podáis subir",
        "Foto de algo que no hay en casa",
        "Foto de un músico o artista callejero",
        "Selfie con un monumento al fondo y cara de sorpresa",
        "Foto de vuestro reflejo en un escaparate o charco",
        "Foto del mercado o tienda más curiosa",
        "Selfie dándoos un beso en un sitio con vistas",
        "Foto de un detalle diminuto que casi nadie mira",
        "Foto de los dos saltando a la vez",
        "Foto con el transporte típico del lugar",
        "Selfie con la bebida típica",
        "Foto artística de una ventana",
        "Selfie de buenos días antes de desayunar",
        "Foto del atardecer desde un sitio nuevo",
        "Foto de una pintada o arte urbano",
        "Selfie con alguien que lleve sombrero",
        "Foto de algo que os haga reír",
        "Foto de las vistas desde vuestro alojamiento"
    ]

    /// Reto del día `dia` para una escapada (siempre el mismo en los dos iPhones).
    static func reto(escapadaId: String, dia: Int) -> String {
        var generador = GeneradorSemilla(semilla: semillaEstable(escapadaId))
        // Barajado propio (Fisher-Yates): el de Swift podría cambiar entre versiones de iOS
        // y entonces cada iPhone vería un reto distinto.
        var barajados = lista
        if barajados.count > 1 {
            for i in stride(from: barajados.count - 1, to: 0, by: -1) {
                let j = Int(generador.next() % UInt64(i + 1))
                barajados.swapAt(i, j)
            }
        }
        return "🎲 Día \(dia): " + barajados[max(0, dia - 1) % barajados.count]
    }

    /// Hash propio: el `hashValue` de Swift cambia cada vez que se abre la app.
    private static func semillaEstable(_ texto: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in texto.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return hash
    }
}

/// Generador de números pseudoaleatorios con semilla (SplitMix64).
struct GeneradorSemilla: RandomNumberGenerator {
    private var estado: UInt64

    init(semilla: UInt64) {
        estado = semilla
    }

    mutating func next() -> UInt64 {
        estado &+= 0x9E3779B97F4A7C15
        var z = estado
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

struct SeccionRetoDelDia: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    let escapada: Escapada

    var body: some View {
        let retos = almacen.retosDe(escapada.id)

        Section {
            if let hoy = escapada.diaDeHoy {
                let textoHoy = RetosSorpresa.reto(escapadaId: escapada.id, dia: hoy)
                let aceptado = retos.contains(where: { $0.texto == textoHoy })

                VStack(alignment: .leading, spacing: 8) {
                    Text(textoHoy)
                        .font(.headline)
                    if aceptado {
                        Label("Aceptado: ya está en vuestra lista de retos", systemImage: "checkmark.seal.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            aceptar(textoHoy)
                        } label: {
                            Label("¡Aceptamos el reto!", systemImage: "hand.raised.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)

                // Retos de días anteriores que no se aceptaron (por si queréis recuperarlos).
                let perdidos = (1..<hoy).map { RetosSorpresa.reto(escapadaId: escapada.id, dia: $0) }
                    .filter { texto in !retos.contains(where: { $0.texto == texto }) }
                ForEach(perdidos, id: \.self) { texto in
                    HStack {
                        Text(texto)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Recuperar") { aceptar(texto) }
                            .font(.caption.bold())
                            .buttonStyle(.borderless)
                    }
                }

                if hoy < escapada.totalDias {
                    Text("🔒 Mañana se desbloquea otro reto sorpresa.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if escapada.yaVivida {
                Text("El viaje ha terminado. Los retos sorpresa que aceptasteis están en la lista de abajo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("🔒 Cada día del viaje se desbloqueará un reto sorpresa. ¡No se puede ver antes!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("🎲 Reto sorpresa del día")
        }
    }

    private func aceptar(_ texto: String) {
        guard !almacen.retosDe(escapada.id).contains(where: { $0.texto == texto }) else { return }
        var reto = Reto()
        reto.escapadaId = escapada.id
        reto.texto = texto
        reto.creadoPorId = sesion.miId
        reto.creadoEn = Date()
        almacen.guardar(reto, en: .retos)
    }
}
