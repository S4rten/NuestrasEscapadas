import SwiftUI

/// Primera pantalla: cada persona escribe su nombre y crea o se une al espacio compartido.
struct BienvenidaView: View {
    @EnvironmentObject var sesion: Sesion
    @EnvironmentObject var almacen: Almacen

    enum Modo: String, CaseIterable, Identifiable {
        case crear = "Crear espacio nuevo"
        case unirme = "Tengo un código"
        var id: String { rawValue }
    }

    @State private var nombre = ""
    @State private var modo: Modo = .crear
    @State private var codigoNuevo = Sesion.generarCodigo()
    @State private var codigoIntroducido = ""
    @State private var consultando = false
    @State private var mensajeError: String? = nil
    @State private var miembrosEncontrados: [Miembro] = []
    @State private var mostrandoQuienEres = false
    @State private var mostrandoConfirmarNuevo = false

    private var codigoActual: String {
        modo == .crear ? codigoNuevo : Sesion.normalizar(codigoIntroducido)
    }

    private var puedeContinuar: Bool {
        !nombre.recortado.isEmpty && Sesion.codigoValido(codigoActual) && !consultando
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Text("✈️")
                            .font(.system(size: 56))
                        Text("Nuestras Escapadas")
                            .font(.title2.bold())
                        Text("Vuestros viajes, planes y gastos, sincronizados entre los dos iPhones.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Tu nombre") {
                    TextField("Cómo te ve tu pareja (ej: Álex)", text: $nombre)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    Picker("Espacio", selection: $modo) {
                        ForEach(Modo.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    if modo == .crear {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Código de vuestro espacio")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(codigoNuevo)
                                .font(.title3.bold().monospaced())
                                .textSelection(.enabled)
                            Text("Tu pareja tendrá que escribir este código en su iPhone. Podrás volver a verlo en Ajustes.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        TextField("Código (ej: K7QM-X2PD-9TRW)", text: $codigoIntroducido)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    }
                } header: {
                    Text("Espacio compartido")
                } footer: {
                    if modo == .unirme {
                        Text("Pídele el código a tu pareja: lo ve en Ajustes (el círculo de arriba a la izquierda).")
                    }
                }

                if let mensajeError {
                    Section {
                        BannerError(mensaje: mensajeError)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section {
                    Button {
                        continuar()
                    } label: {
                        HStack(spacing: 8) {
                            if consultando { ProgressView() }
                            Text(modo == .crear ? "Crear y empezar" : "Unirme")
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!puedeContinuar)
                }
            }
            .navigationTitle("Bienvenidos")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if nombre.isEmpty { nombre = sesion.miNombre }
            }
            .confirmationDialog("¿Quién eres?", isPresented: $mostrandoQuienEres, titleVisibility: .visible) {
                ForEach(miembrosEncontrados) { m in
                    Button("Soy \(m.nombre)") { entrarComo(m) }
                }
                Button("Soy una persona nueva") { entrarNuevo() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Este espacio ya lo usan otras personas. Si ya estabas (por ejemplo, has reinstalado la app), elige tu nombre para recuperar tus gastos.")
            }
            .alert("Ese código es nuevo", isPresented: $mostrandoConfirmarNuevo) {
                Button("Crear espacio con este código") { entrarNuevo() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Todavía no hay nadie con ese código. Si esperabas ver vuestros viajes, revisa que lo has escrito bien.")
            }
        }
    }

    private func continuar() {
        mensajeError = nil
        if modo == .crear {
            sesion.entrar(nombre: nombre, codigo: codigoNuevo)
            return
        }
        let codigo = Sesion.normalizar(codigoIntroducido)
        consultando = true
        Task {
            do {
                let encontrados = try await almacen.consultarMiembros(codigo: codigo, miId: sesion.miId, nombre: nombre.recortado)
                consultando = false
                if encontrados.isEmpty {
                    mostrandoConfirmarNuevo = true
                } else {
                    miembrosEncontrados = encontrados
                    mostrandoQuienEres = true
                }
            } catch {
                consultando = false
                mensajeError = Almacen.mensajeAcceso(error)
            }
        }
    }

    private func entrarComo(_ miembro: Miembro) {
        sesion.entrar(nombre: miembro.nombre, codigo: codigoIntroducido, id: miembro.id)
    }

    private func entrarNuevo() {
        sesion.entrar(nombre: nombre, codigo: codigoIntroducido)
    }
}
