import SwiftUI

// ============================================================================
// PESTAÑA RECUERDO (solo aparece cuando el viaje ya ha terminado)
// Valoración con estrellas + momento favorito + diario del viaje.
// Cada estrella se guarda como un campo suelto, así no se pisa lo del otro.
// ============================================================================

struct RecuerdoSecciones: View {
    @EnvironmentObject var almacen: Almacen
    let escapada: Escapada

    var body: some View {
        let v = escapada.valoracion

        Section {
            if let media = v.media {
                HStack {
                    Text("Nota media del viaje")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    InsigniaMedia(media: media, grande: true)
                }
            }
            FilaEstrellas(titulo: "🏙️ Experiencia en la ciudad", puntuacion: v.experienciaCiudad) {
                guardarNota("experienciaCiudad", $0)
            }
            FilaEstrellas(titulo: "🏛️ Museos y cultura", puntuacion: v.museosCultura) {
                guardarNota("museosCultura", $0)
            }
            FilaEstrellas(titulo: "🍽️ Gastronomía", puntuacion: v.gastronomia) {
                guardarNota("gastronomia", $0)
            }
            FilaEstrellas(titulo: "🛏️ Alojamiento y descanso", puntuacion: v.alojamientoDescanso) {
                guardarNota("alojamientoDescanso", $0)
            }
            FilaEstrellas(titulo: "❤️ Momentos juntos", puntuacion: v.momentosJuntos) {
                guardarNota("momentosJuntos", $0)
            }
        } header: {
            Text("¿Qué tal fue?")
        } footer: {
            Text("Toca una estrella para puntuar; vuelve a tocar la misma para quitarla.")
        }

        Section {
            EditorTextoGuardable(
                titulo: "Nuestro momento favorito",
                valorRemoto: escapada.momentoFavorito,
                placeholder: "Eso que no queréis olvidar nunca…"
            ) { texto in
                almacen.actualizar(escapada.id, en: .escapadas, campos: ["momentoFavorito": texto])
            }
        }

        Section {
            EditorTextoGuardable(
                titulo: "Diario del viaje",
                valorRemoto: escapada.recuerdo,
                placeholder: "Anécdotas, sitios que repetiríais, consejos para la próxima vez…"
            ) { texto in
                almacen.actualizar(escapada.id, en: .escapadas, campos: ["recuerdo": texto])
            }
        } footer: {
            Text("Se guarda al salir del cuadro de texto y se sincroniza con tu pareja.")
        }

        SeccionResumenDiario(escapada: escapada)
    }

    private func guardarNota(_ campo: String, _ nota: Int) {
        almacen.actualizar(escapada.id, en: .escapadas, campos: ["valoracion.\(campo)": nota])
    }
}
