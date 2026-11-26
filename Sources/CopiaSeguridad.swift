import SwiftUI
import UniformTypeIdentifiers

// ============================================================================
// COPIA DE SEGURIDAD: guarda TODO el espacio en un archivo .json (por ejemplo
// en iCloud Drive) y permite recuperarlo. Restaurar solo vuelve a crear lo que
// falta: nunca pisa ni borra lo que ya hay.
// ============================================================================

struct CopiaSeguridad: Codable {
    var version: Int = 1
    var creadaEn: Date = Date()
    var codigo: String = ""
    var escapadas: [Escapada] = []
    var vuelos: [Vuelo] = []
    var trenes: [TrenViaje] = []
    var alojamientos: [Alojamiento] = []
    var gastos: [Gasto] = []
    var checklist: [ItemChecklist] = []
    var actividades: [Actividad] = []
    var ideas: [Idea] = []
    var retos: [Reto] = []
    var pagos: [PagoPareja] = []
    var fechasEspeciales: [FechaEspecial] = []
    var deseos: [Deseo] = []
    var billetes: [Billete] = []
    /// Imágenes (opcional): ID del reto o del billete -> JPEG.
    var fotos: [String: Data] = [:]
    var imagenesBilletes: [String: Data] = [:]

    var totalElementos: Int {
        escapadas.count + vuelos.count + trenes.count + alojamientos.count + gastos.count
            + checklist.count + actividades.count + ideas.count + retos.count + pagos.count
            + fechasEspeciales.count + deseos.count + billetes.count
    }

    static func codificador() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static func decodificador() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }
}

/// Envoltorio para guardar la copia con el selector de archivos de iOS.
struct DocumentoCopia: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var datos: Data

    init(datos: Data) {
        self.datos = datos
    }

    init(configuration: ReadConfiguration) throws {
        datos = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: datos)
    }
}

extension Almacen {
    /// Reúne todo el espacio. Con `conImagenes` descarga también las fotos y billetes.
    func crearCopia(codigo: String, conImagenes: Bool) async -> CopiaSeguridad {
        var c = CopiaSeguridad()
        c.codigo = codigo
        c.escapadas = escapadas
        c.vuelos = vuelos
        c.trenes = trenes
        c.alojamientos = alojamientos
        c.gastos = gastos
        c.checklist = checklist
        c.actividades = actividades
        c.ideas = ideas
        c.retos = retos
        c.pagos = pagos
        c.fechasEspeciales = fechasEspeciales
        c.deseos = deseos
        c.billetes = billetes
        if conImagenes {
            for r in retos where r.completado {
                if let datos = await descargarDatos(.fotos, id: r.id) { c.fotos[r.id] = datos }
            }
            for b in billetes {
                if let datos = await descargarDatos(.billetesDatos, id: b.id) { c.imagenesBilletes[b.id] = datos }
            }
        }
        return c
    }

    /// Vuelve a crear lo que falta. Devuelve cuántos elementos se han recuperado.
    func restaurar(_ c: CopiaSeguridad) -> Int {
        var n = 0
        func recuperar<T: Encodable & Identifiable>(_ lista: [T], _ coleccion: Coleccion) where T.ID == String {
            for elemento in lista where !existe(elemento.id, en: coleccion) {
                guardar(elemento, en: coleccion, anotar: false)
                n += 1
            }
        }
        recuperar(c.escapadas, .escapadas)
        recuperar(c.vuelos, .vuelos)
        recuperar(c.trenes, .trenes)
        recuperar(c.alojamientos, .alojamientos)
        recuperar(c.gastos, .gastos)
        recuperar(c.checklist, .checklist)
        recuperar(c.actividades, .actividades)
        recuperar(c.ideas, .ideas)
        recuperar(c.pagos, .pagos)
        recuperar(c.fechasEspeciales, .fechasEspeciales)
        recuperar(c.deseos, .deseos)

        // Retos y billetes: con su imagen si venía en la copia.
        for r in c.retos where !existe(r.id, en: .retos) {
            var reto = r
            if let datos = c.fotos[r.id] {
                subirDatos(datos, a: .fotos, id: r.id, escapadaId: r.escapadaId)
            } else if reto.completado {
                reto.completado = false          // sin foto: vuelve a quedar pendiente
                reto.fotoEn = nil
            }
            guardar(reto, en: .retos, anotar: false)
            n += 1
        }
        for b in c.billetes where !existe(b.id, en: .billetes) {
            guard let datos = c.imagenesBilletes[b.id] else { continue }
            subirDatos(datos, a: .billetesDatos, id: b.id, escapadaId: b.escapadaId)
            guardar(b, en: .billetes, anotar: false)
            n += 1
        }
        return n
    }
}

/// Sección de Ajustes: crear y restaurar copias.
struct SeccionCopiaSeguridad: View {
    @EnvironmentObject var almacen: Almacen
    @EnvironmentObject var sesion: Sesion

    @AppStorage("escapadas_ultima_copia") private var ultimaCopia: Double = 0
    @State private var conImagenes = true
    @State private var preparando = false
    @State private var documento: DocumentoCopia? = nil
    @State private var exportando = false
    @State private var importando = false
    @State private var copiaLeida: CopiaSeguridad? = nil
    @State private var mensaje: String? = nil

    private var nombreArchivo: String {
        "Escapadas-copia-\(Date().formatted(.iso8601.year().month().day()))"
    }

    var body: some View {
        Section {
            Toggle("Incluir fotos y billetes", isOn: $conImagenes)

            Button {
                crear()
            } label: {
                HStack {
                    Label("Crear copia de seguridad", systemImage: "externaldrive.badge.icloud")
                    Spacer()
                    if preparando { ProgressView() }
                }
            }
            .disabled(preparando)

            Button {
                importando = true
            } label: {
                Label("Restaurar desde una copia", systemImage: "arrow.counterclockwise.icloud")
            }

            if ultimaCopia > 0 {
                Text("Última copia: \(Date(timeIntervalSince1970: ultimaCopia).formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Copia de seguridad")
        } footer: {
            Text("Guárdala en iCloud Drive o en Archivos. Al restaurar solo se recupera lo que falte (nada se pisa ni se borra). Contiene vuestros datos: no la compartas.")
        }
        .fileExporter(isPresented: $exportando, document: documento, contentType: .json, defaultFilename: nombreArchivo) { resultado in
            switch resultado {
            case .success:
                ultimaCopia = Date().timeIntervalSince1970
                mensaje = "Copia guardada correctamente."
            case .failure(let error):
                mensaje = "No se pudo guardar la copia: \(error.localizedDescription)"
            }
            documento = nil
        }
        .fileImporter(isPresented: $importando, allowedContentTypes: [.json]) { resultado in
            leer(resultado)
        }
        .confirmationDialog(
            "¿Restaurar esta copia?",
            isPresented: Binding(get: { copiaLeida != nil }, set: { if !$0 { copiaLeida = nil } }),
            titleVisibility: .visible
        ) {
            Button("Recuperar lo que falte") {
                if let c = copiaLeida {
                    let n = almacen.restaurar(c)
                    mensaje = n == 0
                        ? "No faltaba nada: todo lo de la copia ya estaba en la app."
                        : "Recuperados \(n) \(n == 1 ? "elemento" : "elementos")."
                }
                copiaLeida = nil
            }
            Button("Cancelar", role: .cancel) { copiaLeida = nil }
        } message: {
            if let c = copiaLeida {
                Text("Copia del \(c.creadaEn.formatted(date: .abbreviated, time: .shortened)) con \(c.escapadas.count) escapadas y \(c.totalElementos) elementos en total.\(c.codigo != sesion.codigo ? " Ojo: es de otro espacio (\(c.codigo))." : "")")
            }
        }
        .alert("Copia de seguridad", isPresented: Binding(get: { mensaje != nil }, set: { if !$0 { mensaje = nil } })) {
            Button("Vale", role: .cancel) {}
        } message: {
            Text(mensaje ?? "")
        }
    }

    private func crear() {
        preparando = true
        Task {
            let copia = await almacen.crearCopia(codigo: sesion.codigo, conImagenes: conImagenes)
            preparando = false
            do {
                let datos = try CopiaSeguridad.codificador().encode(copia)
                documento = DocumentoCopia(datos: datos)
                exportando = true
            } catch {
                mensaje = "No se pudo crear la copia: \(error.localizedDescription)"
            }
        }
    }

    private func leer(_ resultado: Result<URL, Error>) {
        switch resultado {
        case .failure(let error):
            mensaje = "No se pudo abrir el archivo: \(error.localizedDescription)"
        case .success(let url):
            let acceso = url.startAccessingSecurityScopedResource()
            defer { if acceso { url.stopAccessingSecurityScopedResource() } }
            do {
                let datos = try Data(contentsOf: url)
                copiaLeida = try CopiaSeguridad.decodificador().decode(CopiaSeguridad.self, from: datos)
            } catch {
                mensaje = "Ese archivo no es una copia de seguridad de Escapadas."
            }
        }
    }
}
