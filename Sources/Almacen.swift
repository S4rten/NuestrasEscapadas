import Foundation
import FirebaseFirestore

// ============================================================================
// ALMACÉN: sincronización en tiempo real con Firestore.
// Cada vuelo, gasto, tarea, etc. es su PROPIO documento, así que si los dos
// editáis a la vez nadie pisa el trabajo del otro.
// ============================================================================

enum EstadoNube: Equatable {
    case desconectado
    case conectando
    case enVivo
    case error(String)

    var texto: String {
        switch self {
        case .desconectado: return "Sin conectar"
        case .conectando: return "Conectando…"
        case .enVivo: return "Sincronizado"
        case .error(let mensaje): return mensaje
        }
    }

    var estaBien: Bool { self == .enVivo }
}

@MainActor
final class Almacen: ObservableObject {
    @Published private(set) var escapadas: [Escapada] = []
    @Published private(set) var vuelos: [Vuelo] = []
    @Published private(set) var trenes: [TrenViaje] = []
    @Published private(set) var alojamientos: [Alojamiento] = []
    @Published private(set) var gastos: [Gasto] = []
    @Published private(set) var checklist: [ItemChecklist] = []
    @Published private(set) var actividades: [Actividad] = []
    @Published private(set) var ideas: [Idea] = []
    @Published private(set) var retos: [Reto] = []
    /// Fotos de retos ya descargadas, por `Reto.claveFoto`. Solo se bajan cuando se ven.
    @Published private(set) var fotosDescargadas: [String: Data] = [:]
    @Published private(set) var miembros: [Miembro] = []
    @Published private(set) var estado: EstadoNube = .desconectado
    @Published private(set) var escapadasCargadas = false

    private var listeners: [ListenerRegistration] = []
    private var codigo = ""
    private var fotosEnDescarga: Set<String> = []

    // MARK: Conexión

    func conectar(codigo: String, miId: String, miNombre: String) {
        if self.codigo == codigo && !listeners.isEmpty {
            registrarMiembro(id: miId, nombre: miNombre)
            return
        }
        desconectar()
        self.codigo = codigo
        estado = .conectando

        let base = Firestore.firestore().collection("parejas").document(codigo)
        registrarMiembro(id: miId, nombre: miNombre)

        escuchar(.escapadas, en: base, destino: \Almacen.escapadas)
        escuchar(.vuelos, en: base, destino: \Almacen.vuelos)
        escuchar(.trenes, en: base, destino: \Almacen.trenes)
        escuchar(.alojamientos, en: base, destino: \Almacen.alojamientos)
        escuchar(.gastos, en: base, destino: \Almacen.gastos)
        escuchar(.checklist, en: base, destino: \Almacen.checklist)
        escuchar(.actividades, en: base, destino: \Almacen.actividades)
        escuchar(.ideas, en: base, destino: \Almacen.ideas)
        escuchar(.retos, en: base, destino: \Almacen.retos)
        escucharMiembros(en: base)
    }

    func desconectar() {
        for l in listeners { l.remove() }
        listeners.removeAll()
        codigo = ""
        escapadas = []
        vuelos = []
        trenes = []
        alojamientos = []
        gastos = []
        checklist = []
        actividades = []
        ideas = []
        retos = []
        fotosDescargadas = [:]
        fotosEnDescarga = []
        miembros = []
        escapadasCargadas = false
        estado = .desconectado
    }

    private func escuchar<T: Decodable>(
        _ coleccion: Coleccion,
        en base: DocumentReference,
        destino: ReferenceWritableKeyPath<Almacen, [T]>
    ) {
        let registro = base.collection(coleccion.rawValue).addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    self.estado = .error("Error de sincronización: \(error.localizedDescription)")
                    return
                }
                guard let documentos = snapshot?.documents else { return }
                var elementos: [T] = []
                for documento in documentos {
                    do {
                        elementos.append(try documento.data(as: T.self))
                    } catch {
                        print("No se pudo leer un documento de \(coleccion.rawValue): \(error)")
                    }
                }
                self[keyPath: destino] = elementos
                self.estado = .enVivo
                if coleccion == .escapadas { self.escapadasCargadas = true }
            }
        }
        listeners.append(registro)
    }

    private func escucharMiembros(en base: DocumentReference) {
        let registro = base.collection("miembros").addSnapshotListener { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self = self else { return }
                if error != nil { return }
                guard let documentos = snapshot?.documents else { return }
                var lista: [Miembro] = []
                for documento in documentos {
                    let nombre = (documento.data()["nombre"] as? String) ?? "Sin nombre"
                    lista.append(Miembro(id: documento.documentID, nombre: nombre))
                }
                self.miembros = lista.sorted { $0.nombre.lowercased() < $1.nombre.lowercased() }
            }
        }
        listeners.append(registro)
    }

    /// Consulta (sin conectarse) quién está ya en un espacio. Se usa al unirse con un código.
    func consultarMiembros(codigo: String) async throws -> [Miembro] {
        let instantanea = try await Firestore.firestore()
            .collection("parejas").document(codigo)
            .collection("miembros").getDocuments()
        var lista: [Miembro] = []
        for documento in instantanea.documents {
            let nombre = (documento.data()["nombre"] as? String) ?? "Sin nombre"
            lista.append(Miembro(id: documento.documentID, nombre: nombre))
        }
        return lista.sorted { $0.nombre.lowercased() < $1.nombre.lowercased() }
    }

    func registrarMiembro(id: String, nombre: String) {
        guard !codigo.isEmpty else { return }
        Firestore.firestore()
            .collection("parejas").document(codigo)
            .collection("miembros").document(id)
            .setData(["id": id, "nombre": nombre], merge: true) { [weak self] error in
                if let error = error {
                    Task { @MainActor in
                        self?.estado = .error("No se pudo registrar tu nombre: \(error.localizedDescription)")
                    }
                }
            }
    }

    // MARK: Personas

    func nombre(de id: String, miId: String) -> String {
        if id == miId { return "Tú" }
        return miembros.first(where: { $0.id == id })?.nombre ?? "Tu pareja"
    }

    func nombreDePareja(miId: String) -> String {
        miembros.first(where: { $0.id != miId })?.nombre ?? "Tu pareja"
    }

    func hayPareja(miId: String) -> Bool {
        miembros.contains(where: { $0.id != miId })
    }

    // MARK: Consultas por escapada

    func escapada(_ id: String) -> Escapada? {
        escapadas.first(where: { $0.id == id })
    }

    func vuelosDe(_ id: String) -> [Vuelo] {
        vuelos.filter { $0.escapadaId == id }.sorted { $0.fechaHoraSalida < $1.fechaHoraSalida }
    }

    func trenesDe(_ id: String) -> [TrenViaje] {
        trenes.filter { $0.escapadaId == id }.sorted { $0.fechaHoraSalida < $1.fechaHoraSalida }
    }

    func alojamientosDe(_ id: String) -> [Alojamiento] {
        alojamientos.filter { $0.escapadaId == id }.sorted { $0.entrada < $1.entrada }
    }

    func gastosDe(_ id: String) -> [Gasto] {
        gastos.filter { $0.escapadaId == id }.sorted { $0.fecha > $1.fecha }
    }

    func checklistDe(_ id: String) -> [ItemChecklist] {
        checklist.filter { $0.escapadaId == id }.sorted { $0.creadoEn < $1.creadoEn }
    }

    func actividadesDe(_ id: String) -> [Actividad] {
        actividades.filter { $0.escapadaId == id }.sorted { $0.creadaEn < $1.creadaEn }
    }

    func ideasDe(_ id: String) -> [Idea] {
        ideas.filter { $0.escapadaId == id }.sorted { $0.creadaEn < $1.creadaEn }
    }

    func retosDe(_ id: String) -> [Reto] {
        retos.filter { $0.escapadaId == id }.sorted { $0.creadoEn < $1.creadoEn }
    }

    func reto(_ id: String) -> Reto? {
        retos.first(where: { $0.id == id })
    }

    func totalGastado(_ id: String) -> Double {
        gastosDe(id).reduce(0) { $0 + $1.importe }
    }

    /// Primera salida (vuelo o tren) del día de inicio, para la cuenta atrás.
    func primeraSalida(de escapada: Escapada) -> Date? {
        let inicio = escapada.fechaInicio.inicioDelDia
        let fin = inicio.sumando(dias: 1)
        let fechas = vuelosDe(escapada.id).map { $0.fechaHoraSalida } + trenesDe(escapada.id).map { $0.fechaHoraSalida }
        return fechas.filter { $0 >= inicio && $0 < fin }.min()
    }

    // MARK: Escritura

    private func referencia(_ coleccion: Coleccion, _ id: String) -> DocumentReference {
        Firestore.firestore()
            .collection("parejas").document(codigo)
            .collection(coleccion.rawValue).document(id)
    }

    private func registrarFallo(_ error: Error, _ accion: String) {
        estado = .error("No se pudo \(accion): \(error.localizedDescription)")
    }

    /// Crea o reemplaza un documento completo (solo para elementos nuevos o formularios completos).
    func guardar<T: Encodable & Identifiable>(_ valor: T, en coleccion: Coleccion) where T.ID == String {
        guard !codigo.isEmpty else { return }
        do {
            try referencia(coleccion, valor.id).setData(from: valor, merge: false) { [weak self] error in
                if let error = error {
                    Task { @MainActor in self?.registrarFallo(error, "guardar") }
                }
            }
        } catch {
            registrarFallo(error, "guardar")
        }
    }

    /// Cambia solo algunos campos de un documento (no pisa el resto).
    func actualizar(_ id: String, en coleccion: Coleccion, campos: [String: Any]) {
        guard !codigo.isEmpty else { return }
        referencia(coleccion, id).updateData(campos) { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "actualizar") }
            }
        }
    }

    func borrar(id: String, de coleccion: Coleccion) {
        guard !codigo.isEmpty else { return }
        referencia(coleccion, id).delete { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "borrar") }
            }
        }
    }

    /// Borra la escapada y todo lo que cuelga de ella en una sola operación.
    func borrarEscapada(_ escapada: Escapada) {
        guard !codigo.isEmpty else { return }
        let lote = Firestore.firestore().batch()
        for v in vuelos where v.escapadaId == escapada.id { lote.deleteDocument(referencia(.vuelos, v.id)) }
        for t in trenes where t.escapadaId == escapada.id { lote.deleteDocument(referencia(.trenes, t.id)) }
        for a in alojamientos where a.escapadaId == escapada.id { lote.deleteDocument(referencia(.alojamientos, a.id)) }
        for g in gastos where g.escapadaId == escapada.id { lote.deleteDocument(referencia(.gastos, g.id)) }
        for c in checklist where c.escapadaId == escapada.id { lote.deleteDocument(referencia(.checklist, c.id)) }
        for a in actividades where a.escapadaId == escapada.id { lote.deleteDocument(referencia(.actividades, a.id)) }
        for i in ideas where i.escapadaId == escapada.id { lote.deleteDocument(referencia(.ideas, i.id)) }
        for r in retos where r.escapadaId == escapada.id {
            lote.deleteDocument(referencia(.retos, r.id))
            lote.deleteDocument(referencia(.fotos, r.id))
        }
        lote.deleteDocument(referencia(.escapadas, escapada.id))
        lote.commit { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "borrar la escapada") }
            }
        }
    }

    // MARK: Fotos de los retos
    // La foto (JPEG comprimido, < 1 MB) va en "fotos/{idDelReto}" para que la lista de retos
    // se sincronice rápido y cada foto se descargue solo cuando alguien la mira.

    /// Sube la foto y marca el reto como completado, todo en una sola operación.
    func guardarFoto(_ datos: Data, para reto: Reto, miId: String) {
        guard !codigo.isEmpty else { return }
        let ahora = Date()
        var actualizado = reto
        actualizado.fotoEn = ahora
        fotosDescargadas[actualizado.claveFoto] = datos

        let lote = Firestore.firestore().batch()
        lote.setData([
            "id": reto.id,
            "escapadaId": reto.escapadaId,
            "datos": datos
        ], forDocument: referencia(.fotos, reto.id))
        lote.updateData([
            "completado": true,
            "completadoPorId": miId,
            "fotoEn": ahora
        ], forDocument: referencia(.retos, reto.id))
        lote.commit { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "subir la foto") }
            }
        }
    }

    /// Quita la foto y deja el reto pendiente otra vez.
    func quitarFoto(de reto: Reto) {
        guard !codigo.isEmpty else { return }
        fotosDescargadas[reto.claveFoto] = nil
        let lote = Firestore.firestore().batch()
        lote.deleteDocument(referencia(.fotos, reto.id))
        lote.updateData([
            "completado": false,
            "completadoPorId": "",
            "fotoEn": FieldValue.delete()
        ], forDocument: referencia(.retos, reto.id))
        lote.commit { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "quitar la foto") }
            }
        }
    }

    /// Borra el reto y su foto.
    func borrarReto(_ reto: Reto) {
        guard !codigo.isEmpty else { return }
        fotosDescargadas[reto.claveFoto] = nil
        let lote = Firestore.firestore().batch()
        lote.deleteDocument(referencia(.retos, reto.id))
        lote.deleteDocument(referencia(.fotos, reto.id))
        lote.commit { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "borrar el reto") }
            }
        }
    }

    /// Descarga la foto de un reto si aún no está en memoria.
    func cargarFoto(de reto: Reto) {
        guard !codigo.isEmpty, reto.completado else { return }
        let clave = reto.claveFoto
        guard fotosDescargadas[clave] == nil, !fotosEnDescarga.contains(clave) else { return }
        fotosEnDescarga.insert(clave)
        referencia(.fotos, reto.id).getDocument { [weak self] snapshot, _ in
            let datos = snapshot?.data()?["datos"] as? Data
            Task { @MainActor in
                guard let self = self else { return }
                self.fotosEnDescarga.remove(clave)
                if let datos = datos {
                    self.fotosDescargadas[clave] = datos
                }
            }
        }
    }
}
