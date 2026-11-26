import SwiftUI
import UIKit

// ============================================================================
// AJUSTES: estado de la sincronización, nombre, código del espacio, miembros,
// divisas y salir del espacio.
// ============================================================================

struct AjustesView: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @EnvironmentObject var divisas: ServicioDivisas
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var red = MonitorConexion.compartido

    @State private var nombre = ""
    @State private var confirmandoSalida = false

    private var idCorto: String {
        String(sesion.miId.prefix(8))
    }

    private var nombreCambiado: Bool {
        let limpio = nombre.recortado
        return !limpio.isEmpty && limpio != sesion.miNombre
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Sincronización") {
                    HStack {
                        Circle()
                            .fill(almacen.estado.estaBien ? Color.green : Color.orange)
                            .frame(width: 10, height: 10)
                        Text(almacen.estado.texto)
                            .font(.subheadline)
                    }
                    if !red.hayConexion || almacen.subidaRetrasada {
                        BannerSinConexion()
                    }
                }

                Section {
                    NavigationLink {
                        FechasEspecialesView()
                    } label: {
                        HStack {
                            Label("Fechas especiales", systemImage: "heart.circle.fill")
                            Spacer()
                            if !almacen.fechasEspeciales.isEmpty {
                                Text("\(almacen.fechasEspeciales.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Aniversarios, cumpleaños… Os avisaremos en Próximas cuando falte poco para planear una escapada.")
                }

                Section {
                    TextField("Tu nombre", text: $nombre)
                    if nombreCambiado {
                        Button("Guardar nombre") {
                            sesion.cambiarNombre(nombre)
                            almacen.registrarMiembro(id: sesion.miId, nombre: sesion.miNombre)
                        }
                    }
                    HStack {
                        Text("ID de este iPhone")
                        Spacer()
                        Text(idCorto)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Este iPhone")
                } footer: {
                    Text("Cada iPhone tiene su propio ID único; así se sabe quién pagó cada gasto y a quién toca cada tarea.")
                }

                Section {
                    HStack {
                        Text(sesion.codigo)
                            .font(.body.monospaced().bold())
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = sesion.codigo
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                    }
                    ShareLink(item: "Únete a nuestras escapadas con este código: \(sesion.codigo)") {
                        Label("Compartir código con mi pareja", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Código del espacio")
                } footer: {
                    Text("Tu pareja lo escribe al abrir la app por primera vez. No lo publiques. Cuando estéis los dos dentro, cierra el espacio en «Seguridad» y nadie más podrá entrar aunque tenga el código.")
                }

                Section("Miembros") {
                    if almacen.miembros.isEmpty {
                        Text("Cargando…")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(almacen.miembros) { m in
                        HStack {
                            Image(systemName: m.id == sesion.miId ? "person.fill" : "person")
                            Text(m.nombre)
                            Spacer()
                            if m.id == sesion.miId {
                                Chip(texto: "Tú")
                            }
                        }
                    }
                    if !almacen.hayPareja(miId: sesion.miId) && !almacen.miembros.isEmpty {
                        Text("Aún no se ha unido tu pareja. Pásale el código de arriba.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SeccionSeguridad()

                SeccionAjustesAvisos()

                SeccionCopiaSeguridad()

                SeccionClaveVuelos()

                Section {
                    Button {
                        Task { await divisas.actualizar() }
                    } label: {
                        HStack {
                            Label("Actualizar tasas de cambio", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if divisas.cargando {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(divisas.cargando)

                    if let fecha = divisas.ultimaActualizacion {
                        Text("Última actualización: \(fecha.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error = divisas.errorUltimaCarga {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Divisas")
                } footer: {
                    Text("Las tasas son orientativas y se pueden corregir a mano al añadir cada gasto.")
                }

                Section {
                    Button(role: .destructive) {
                        confirmandoSalida = true
                    } label: {
                        Label("Salir de este espacio", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } footer: {
                    Text("No borra ningún viaje: siguen guardados en la nube. Podrás volver a entrar con el código.")
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
            .onAppear { nombre = sesion.miNombre }
            .onDisappear {
                // Por si se cambiaron los avisos: reprogramarlos con lo último.
                Task { await Avisos.compartido.reprogramar(almacen: almacen, miId: sesion.miId) }
            }
            .confirmationDialog("¿Salir de este espacio?", isPresented: $confirmandoSalida, titleVisibility: .visible) {
                Button("Salir", role: .destructive) {
                    almacen.desconectar()
                    sesion.salir()
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Apunta el código \(sesion.codigo) antes de salir para poder volver a entrar.")
            }
        }
    }
}

// ============================================================================
// SEGURIDAD: cerrar el espacio a iPhones nuevos y ver qué iPhones tienen acceso.
// ============================================================================

struct SeccionSeguridad: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion
    @State private var revocando: Acceso? = nil

    var body: some View {
        let cerrado = Binding(
            get: { almacen.espacioCerrado },
            set: { almacen.cambiarCierre($0) }
        )

        Section {
            Toggle(isOn: cerrado) {
                Label("Cerrar a iPhones nuevos", systemImage: almacen.espacioCerrado ? "lock.fill" : "lock.open")
            }

            ForEach(almacen.accesos.sorted { $0.creadoEn < $1.creadoEn }) { acceso in
                HStack {
                    Image(systemName: "iphone")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(acceso.nombre.isEmpty ? "iPhone sin nombre" : acceso.nombre)
                        Text("Desde el \(acceso.creadoEn.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if acceso.id == almacen.miUid {
                        Chip(texto: "Este iPhone")
                    }
                }
                .swipeActions(edge: .trailing) {
                    if acceso.id != almacen.miUid {
                        Button(role: .destructive) {
                            revocando = acceso
                        } label: {
                            Label("Quitar", systemImage: "xmark.circle")
                        }
                    }
                }
            }
        } header: {
            Text("Seguridad")
        } footer: {
            Text(almacen.espacioCerrado
                 ? "🔒 Cerrado: aunque alguien tenga el código, no podrá entrar. Si cambiáis de iPhone o reinstaláis la app, ábrelo un momento desde el otro iPhone."
                 : "🔓 Abierto: cualquiera con el código puede unirse. Cerradlo cuando estéis los dos dentro. Desliza un iPhone para quitarle el acceso.")
        }
        .confirmationDialog("¿Quitar el acceso a este iPhone?", isPresented: Binding(
            get: { revocando != nil },
            set: { if !$0 { revocando = nil } }
        ), titleVisibility: .visible) {
            Button("Quitar acceso", role: .destructive) {
                if let a = revocando { almacen.revocarAcceso(a) }
                revocando = nil
            }
            Button("Cancelar", role: .cancel) { revocando = nil }
        } message: {
            Text("Dejará de ver y editar vuestros viajes. Si el espacio está abierto, podrá volver a entrar con el código.")
        }
    }
}
