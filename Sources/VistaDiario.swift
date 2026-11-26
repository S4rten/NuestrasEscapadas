import SwiftUI

// ============================================================================
// DIARIO DE CADA DÍA: un emoji y una nota por día del viaje.
//  · SeccionDiarioDia:     en la pestaña Plan (desde que llega ese día)
//  · SeccionResumenDiario: en la pestaña Recuerdo, el viaje día a día
// Cada campo se guarda por separado, así no se pisa lo que escribe el otro.
// ============================================================================

enum EmojisDia {
    static let lista = ["😍", "🥰", "😄", "🤩", "😌", "😋", "🥳", "😴", "😅", "🥵", "🥶", "🌧️"]
}

struct SeccionDiarioDia: View {
    @EnvironmentObject var almacen: Almacen
    let escapada: Escapada
    let dia: Int

    var body: some View {
        // Solo se puede escribir desde que llega ese día.
        if escapada.fechaParaDia(dia) <= Date() {
            let diario = almacen.diario(de: escapada.id, dia: dia)
            let emojiActual = diario?.emoji ?? ""

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(EmojisDia.lista, id: \.self) { e in
                            Text(e)
                                .font(.title2)
                                .padding(6)
                                .background(emojiActual == e ? Color.accentColor.opacity(0.2) : Color.clear)
                                .clipShape(Circle())
                                .onTapGesture {
                                    guardar(["emoji": emojiActual == e ? "" : e])
                                }
                        }
                    }
                }

                EditorTextoGuardable(
                    titulo: "¿Cómo ha ido el día \(dia)?",
                    valorRemoto: diario?.nota ?? "",
                    placeholder: "Lo mejor del día, una anécdota, dónde comisteis…"
                ) { texto in
                    guardar(["nota": texto])
                }
                // Un editor nuevo por día, para que nunca se guarde el texto en el día equivocado.
                .id("diario-\(escapada.id)-\(dia)")
            } header: {
                Text("Diario del día \(dia)")
            } footer: {
                Text("Elegid el emoji del día y escribid lo que no queréis olvidar. Al final del viaje lo veréis todo junto en Recuerdo.")
            }
        }
    }

    private func guardar(_ campos: [String: Any]) {
        let id = DiarioDia.idPara(escapadaId: escapada.id, dia: dia)
        var todo = campos
        todo["id"] = id
        todo["escapadaId"] = escapada.id
        todo["dia"] = dia
        almacen.guardarCampos(id, en: .diarios, campos: todo)
    }
}

struct SeccionResumenDiario: View {
    @EnvironmentObject var almacen: Almacen
    let escapada: Escapada

    var body: some View {
        let dias = almacen.diariosDe(escapada.id)
            .filter { !$0.emoji.isEmpty || !$0.nota.recortado.isEmpty }

        if !dias.isEmpty {
            Section {
                ForEach(dias) { d in
                    HStack(alignment: .top, spacing: 12) {
                        Text(d.emoji.isEmpty ? "📅" : d.emoji)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Día \(d.dia) · \(escapada.fechaParaDia(d.dia).formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            if !d.nota.recortado.isEmpty {
                                Text(d.nota)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("El viaje día a día")
            }
        }
    }
}
