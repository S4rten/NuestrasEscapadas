import SwiftUI

// ============================================================================
// FECHAS ESPECIALES: aniversarios, cumpleaños… compartidas entre los dos.
//  · FechasEspecialesView:   lista y alta (desde Ajustes)
//  · TarjetaFechaEspecial:   aviso en Próximas cuando falta poco, con botón
//                            para planear una escapada para esa fecha
// ============================================================================

enum EmojisFecha {
    static let lista = ["💍", "❤️", "🎂", "🥂", "🏠", "💋", "🐶", "✨", "🎉", "🌹"]
}

struct FechasEspecialesView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    @State private var titulo = ""
    @State private var emoji = "💍"
    @State private var fecha = Date()
    @State private var anual = true

    var body: some View {
        Form {
            Section {
                HStack {
                    Menu {
                        ForEach(EmojisFecha.lista, id: \.self) { e in
                            Button(e) { emoji = e }
                        }
                    } label: {
                        Text(emoji)
                            .font(.title2)
                    }
                    TextField("Ej: Nuestro aniversario", text: $titulo)
                }
                DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
                Toggle("Se repite cada año", isOn: $anual)
                Button {
                    anadir()
                } label: {
                    Label("Añadir fecha", systemImage: "plus.circle.fill")
                }
                .disabled(titulo.recortado.isEmpty)
            } header: {
                Text("Nueva fecha especial")
            } footer: {
                Text("Para aniversarios y cumpleaños, pon la fecha original (ej: el día que empezasteis): la app calcula los años que cumplís.")
            }

            Section("Vuestras fechas") {
                if almacen.fechasEspeciales.isEmpty {
                    Text("Aún no hay ninguna.")
                        .foregroundStyle(.secondary)
                }
                ForEach(almacen.fechasEspecialesOrdenadas) { f in
                    FilaFechaEspecial(fecha: f)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                almacen.borrar(id: f.id, de: .fechasEspeciales)
                            } label: {
                                Label("Borrar", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle("Fechas especiales")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func anadir() {
        let t = titulo.recortado
        guard !t.isEmpty else { return }
        var f = FechaEspecial()
        f.titulo = t
        f.emoji = emoji
        f.fecha = fecha.inicioDelDia.conHora(12)   // mediodía: evita saltos de día por zona horaria
        f.anual = anual
        f.creadaPorId = sesion.miId
        almacen.guardar(f, en: .fechasEspeciales)
        titulo = ""
    }
}

struct FilaFechaEspecial: View {
    let fecha: FechaEspecial

    var body: some View {
        HStack(spacing: 12) {
            Text(fecha.emoji)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(fecha.titulo)
                    .font(.subheadline.weight(.medium))
                Text(subtitulo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let dias = fecha.diasHasta() {
                Chip(texto: dias == 0 ? "¡Hoy!" : "En \(dias)d", color: dias <= 30 ? .pink : .secondary)
            } else {
                Chip(texto: "Pasada", color: .secondary)
            }
        }
    }

    private var subtitulo: String {
        var partes: [String] = []
        if let proxima = fecha.proximaOcurrencia() {
            partes.append(proxima.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
        } else {
            partes.append(fecha.fecha.formatted(date: .long, time: .omitted))
        }
        if let anos = fecha.anosQueSeCumplen() {
            partes.append("cumplís \(anos) \(anos == 1 ? "año" : "años")")
        }
        if fecha.anual { partes.append("cada año") }
        return partes.joined(separator: " · ")
    }
}

/// Aviso en Próximas de la siguiente fecha especial (si falta poco).
struct TarjetaFechaEspecial: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    let alPlanear: (Date) -> Void

    /// Con cuántos días de antelación aparece el aviso.
    static let diasAviso = 60

    var body: some View {
        if let f = almacen.fechasEspecialesOrdenadas.first,
           let dias = f.diasHasta(), dias <= Self.diasAviso,
           let proxima = f.proximaOcurrencia() {
            let planCercano = almacen.escapadas.first { e in
                !e.sorpresaOculta(para: sesion.miId)
                    && e.fechaInicio.inicioDelDia <= proxima.sumando(dias: 3)
                    && e.fechaFin.inicioDelDia >= proxima.sumando(dias: -3)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(f.emoji)
                        .font(.system(size: 30))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.titulo)
                            .font(.headline)
                        Text(textoCuando(f, dias: dias, proxima: proxima))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                if let plan = planCercano {
                    Label("Ya tenéis plan: \(plan.icono) \(plan.titulo)", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                } else if dias > 0 {
                    Button {
                        alPlanear(proxima)
                    } label: {
                        Label("Planear una escapada para esa fecha", systemImage: "airplane")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.pink.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func textoCuando(_ f: FechaEspecial, dias: Int, proxima: Date) -> String {
        var texto = dias == 0 ? "¡Es hoy!" : (dias == 1 ? "Mañana" : "En \(dias) días")
        texto += " · " + proxima.formatted(.dateTime.day().month(.wide))
        if let anos = f.anosQueSeCumplen() {
            texto += " · cumplís \(anos) \(anos == 1 ? "año" : "años")"
        }
        return texto
    }
}
