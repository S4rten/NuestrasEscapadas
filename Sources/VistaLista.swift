import SwiftUI

// ============================================================================
// PESTAÑA LISTA: preparativos compartidos + notas e ideas
// ============================================================================

private struct OpcionAsignacion: Identifiable {
    let id: String          // "" = ambos
    let etiqueta: String
}

struct ListaSecciones: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    let escapada: Escapada
    var mostrarIdeas: Bool = true

    @State private var textoTarea = ""
    @State private var asignadoA = ""
    @State private var textoIdea = ""

    private var opciones: [OpcionAsignacion] {
        var lista = [
            OpcionAsignacion(id: "", etiqueta: "Ambos"),
            OpcionAsignacion(id: sesion.miId, etiqueta: "Yo")
        ]
        for miembro in almacen.miembros where miembro.id != sesion.miId {
            lista.append(OpcionAsignacion(id: miembro.id, etiqueta: miembro.nombre))
        }
        return lista
    }

    private func etiquetaAsignacion(_ id: String) -> String {
        if id.isEmpty { return "Ambos" }
        if id == sesion.miId { return "Yo" }
        return almacen.miembros.first(where: { $0.id == id })?.nombre ?? "Pareja"
    }

    var body: some View {
        let tareas = almacen.checklistDe(escapada.id)
        let hechas = tareas.filter { $0.completado }.count

        Section {
            HStack(spacing: 10) {
                TextField("¿Qué hay que llevar o preparar?", text: $textoTarea)
                    .onSubmit { anadirTarea() }
                Button {
                    anadirTarea()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .disabled(textoTarea.recortado.isEmpty)
            }

            Picker("Asignado a", selection: $asignadoA) {
                ForEach(opciones) { opcion in
                    Text(opcion.etiqueta).tag(opcion.id)
                }
            }
            .pickerStyle(.segmented)

            ForEach(tareas) { tarea in
                HStack(spacing: 10) {
                    Image(systemName: tarea.completado ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(tarea.completado ? Color.accentColor : Color.secondary)
                    Text(tarea.texto)
                        .strikethrough(tarea.completado)
                        .foregroundStyle(tarea.completado ? Color.secondary : Color.primary)
                    Spacer()
                    Chip(texto: etiquetaAsignacion(tarea.asignadoAId), color: .secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    almacen.actualizar(tarea.id, en: .checklist, campos: ["completado": !tarea.completado])
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        almacen.borrar(id: tarea.id, de: .checklist)
                    } label: {
                        Label("Borrar", systemImage: "trash")
                    }
                }
            }
        } header: {
            HStack {
                Text("Checklist compartida")
                Spacer()
                if !tareas.isEmpty {
                    Text("\(hechas)/\(tareas.count)")
                        .font(.caption.bold())
                }
            }
        }

        if mostrarIdeas {
            Section {
                HStack(spacing: 10) {
                    TextField("Idea, restaurante o enlace…", text: $textoIdea)
                        .onSubmit { anadirIdea() }
                    Button {
                        anadirIdea()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(textoIdea.recortado.isEmpty)
                }

                ForEach(almacen.ideasDe(escapada.id)) { idea in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(idea.texto)
                            .font(.subheadline)
                        HStack(spacing: 8) {
                            if idea.autorId != sesion.miId {
                                Text("de \(almacen.nombre(de: idea.autorId, miId: sesion.miId))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if idea.texto.lowercased().hasPrefix("http"), let enlace = urlDesdeTexto(idea.texto) {
                                BotonEnlace(titulo: "Abrir", url: enlace)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            almacen.borrar(id: idea.id, de: .ideas)
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("Notas rápidas e ideas")
            }
        }
    }

    private func anadirTarea() {
        let texto = textoTarea.recortado
        guard !texto.isEmpty else { return }
        var tarea = ItemChecklist()
        tarea.escapadaId = escapada.id
        tarea.texto = texto
        tarea.asignadoAId = asignadoA
        almacen.guardar(tarea, en: .checklist)
        textoTarea = ""
    }

    private func anadirIdea() {
        let texto = textoIdea.recortado
        guard !texto.isEmpty else { return }
        var idea = Idea()
        idea.escapadaId = escapada.id
        idea.texto = texto
        idea.autorId = sesion.miId
        almacen.guardar(idea, en: .ideas)
        textoIdea = ""
    }
}
