import Foundation
import FirebaseAuth
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
    @Published private(set) var pagos: [PagoPareja] = []
    @Published private(set) var fechasEspeciales: [FechaEspecial] = []
    @Published private(set) var deseos: [Deseo] = []
    @Published private(set) var accesos: [Acceso] = []
    @Published private(set) var novedades: [Novedad] = []
    @Published private(set) var billetes: [Billete] = []
    @Published private(set) var opciones: [Opcion] = []
    @Published private(set) var huchas: [Hucha] = []
    @Published private(set) var aportaciones: [Aportacion] = []
    /// Imágenes de billetes ya descargadas, por ID. Solo se bajan cuando se ven.
    @Published private(set) var billetesDescargados: [String: Data] = [:]
    /// true si el espacio no admite iPhones nuevos (se cambia en Ajustes).
    @Published private(set) var espacioCerrado = false
    /// UID anónimo de Firebase de este iPhone.
    @Published private(set) var miUid = ""
    /// true mientras haya cambios guardados en este iPhone que aún no han llegado a la nube.
    @Published private(set) var cambiosPendientes = false {
        didSet { programarAvisoSubida() }
    }
    /// Como `cambiosPendientes`, pero solo si llevan más de 3 s sin subir
    /// (así el aviso no parpadea con cada cambio normal hecho con conexión).
    @Published private(set) var subidaRetrasada = false
    private var tareaAvisoSubida: Task<Void, Never>? = nil

    private func programarAvisoSubida() {
        tareaAvisoSubida?.cancel()
        guard cambiosPendientes else {
            if subidaRetrasada { subidaRetrasada = false }
            return
        }
        tareaAvisoSubida = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, let self = self, self.cambiosPendientes else { return }
            self.subidaRetrasada = true
        }
    }
    /// Fotos de retos ya descargadas, por `Reto.claveFoto`. Solo se bajan cuando se ven.
    @Published private(set) var fotosDescargadas: [String: Data] = [:]
    @Published private(set) var miembros: [Miembro] = []
    @Published private(set) var estado: EstadoNube = .desconectado
    @Published private(set) var escapadasCargadas = false

    private var listeners: [ListenerRegistration] = []
    private var codigo = ""
    private var fotosEnDescarga: Set<String> = []
    private var billetesEnDescarga: Set<String> = []
    private var pendientesPorColeccion: [String: Bool] = [:]
    private var miId = ""
    private var novedadesLimpiadas = false

    // MARK: Seguridad (inicio de sesión anónimo)
    // Cada iPhone inicia sesión de forma anónima e invisible en Firebase. Las reglas
    // solo dejan leer y escribir a los iPhones que tienen un documento en "accesos".

    /// Devuelve el UID de este iPhone, iniciando sesión anónima si hace falta.
    private func usuarioAnonimo() async throws -> String {
        if let actual = Auth.auth().currentUser {
            miUid = actual.uid
            return actual.uid
        }
        let resultado = try await Auth.auth().signInAnonymously()
        miUid = resultado.user.uid
        return resultado.user.uid
    }

    private func claveAccesoConfirmado(_ codigo: String, _ uid: String) -> String {
        "escapadas_acceso_\(codigo)_\(uid)"
    }

    /// Registra este iPhone en "accesos". Si ya se confirmó otra vez, no espera a la red
    /// (así la app abre al momento aunque no haya conexión).
    private func asegurarAcceso(codigo: String, miId: String, nombre: String) async throws {
        let uid = try await usuarioAnonimo()
        let referencia = Firestore.firestore()
            .collection("parejas").document(codigo)
            .collection(Coleccion.accesos.rawValue).document(uid)
        let datos: [String: Any] = ["id": uid, "miId": miId, "nombre": nombre, "creadoEn": Date()]
        let clave = claveAccesoConfirmado(codigo, uid)
        if UserDefaults.standard.bool(forKey: clave) {
            // Con bloque de respuesta: así no espera a la red (sirve sin conexión).
            referencia.setData(["miId": miId, "nombre": nombre], merge: true) { _ in }
            return
        }
        try await referencia.setData(datos)
        UserDefaults.standard.set(true, forKey: clave)
    }

    /// Mensaje claro cuando Firebase rechaza la entrada.
    static func mensajeAcceso(_ error: Error) -> String {
        let ns = error as NSError
        // 7 = permiso denegado (Firestore) · 17006 = método de acceso desactivado (Auth)
        if ns.domain == "FIRFirestoreErrorDomain" && ns.code == 7 {
            return "Este espacio está cerrado a iPhones nuevos. Pide a tu pareja que lo abra en Ajustes › Seguridad."
        }
        if ns.domain == "FIRAuthErrorDomain" && ns.code == 17006 {
            return "Falta activar el inicio de sesión anónimo en la consola de Firebase (Authentication › Método de acceso › Anónimo)."
        }
        return "No se pudo entrar en el espacio: \(error.localizedDescription)"
    }

    /// Cierra o abre el espacio a iPhones nuevos.
    func cambiarCierre(_ cerrado: Bool) {
        guard !codigo.isEmpty else { return }
        Firestore.firestore().collection("parejas").document(codigo)
            .setData(["cerrado": cerrado], merge: true) { [weak self] error in
                if let error = error {
                    Task { @MainActor in self?.registrarFallo(error, "cambiar la seguridad") }
                }
            }
    }

    /// Quita el permiso a un iPhone (por ejemplo, uno antiguo o perdido).
    func revocarAcceso(_ acceso: Acceso) {
        guard acceso.id != miUid else { return }
        borrar(id: acceso.id, de: .accesos)
    }

    // MARK: Conexión

    func conectar(codigo: String, miId: String, miNombre: String) async {
        if self.codigo == codigo && !listeners.isEmpty {
            registrarMiembro(id: miId, nombre: miNombre)
            return
        }
        desconectar()
        self.codigo = codigo
        self.miId = miId
        estado = .conectando

        do {
            try await asegurarAcceso(codigo: codigo, miId: miId, nombre: miNombre)
        } catch {
            if self.codigo == codigo { estado = .error(Almacen.mensajeAcceso(error)) }
            return
        }
        // Si mientras tanto se salió del espacio o se cambió de código, no seguir.
        guard self.codigo == codigo, listeners.isEmpty else { return }

        let base = Firestore.firestore().collection("parejas").document(codigo)
        registrarMiembro(id: miId, nombre: miNombre)
        escucharEspacio(base)

        escuchar(.escapadas, en: base, destino: \Almacen.escapadas)
        escuchar(.vuelos, en: base, destino: \Almacen.vuelos)
        escuchar(.trenes, en: base, destino: \Almacen.trenes)
        escuchar(.alojamientos, en: base, destino: \Almacen.alojamientos)
        escuchar(.gastos, en: base, destino: \Almacen.gastos)
        escuchar(.checklist, en: base, destino: \Almacen.checklist)
        escuchar(.actividades, en: base, destino: \Almacen.actividades)
        escuchar(.ideas, en: base, destino: \Almacen.ideas)
        escuchar(.retos, en: base, destino: \Almacen.retos)
        escuchar(.pagos, en: base, destino: \Almacen.pagos)
        escuchar(.fechasEspeciales, en: base, destino: \Almacen.fechasEspeciales)
        escuchar(.deseos, en: base, destino: \Almacen.deseos)
        escuchar(.accesos, en: base, destino: \Almacen.accesos)
        escuchar(.novedades, en: base, destino: \Almacen.novedades)
        escuchar(.billetes, en: base, destino: \Almacen.billetes)
        escuchar(.opciones, en: base, destino: \Almacen.opciones)
        escuchar(.huchas, en: base, destino: \Almacen.huchas)
        escuchar(.aportaciones, en: base, destino: \Almacen.aportaciones)
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
        pagos = []
        fechasEspeciales = []
        deseos = []
        accesos = []
        novedades = []
        billetes = []
        opciones = []
        huchas = []
        aportaciones = []
        billetesDescargados = [:]
        billetesEnDescarga = []
        espacioCerrado = false
        novedadesLimpiadas = false
        pendientesPorColeccion = [:]
        cambiosPendientes = false
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
        // includeMetadataChanges: también avisa cuando un cambio hecho sin conexión llega a la nube.
        let registro = base.collection(coleccion.rawValue).addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let error = error {
                    self.estado = .error("Error de sincronización: \(error.localizedDescription)")
                    return
                }
                if let metadatos = snapshot?.metadata {
                    self.pendientesPorColeccion[coleccion.rawValue] = metadatos.hasPendingWrites
                    let hayPendientes = self.pendientesPorColeccion.values.contains(true)
                    if hayPendientes != self.cambiosPendientes { self.cambiosPendientes = hayPendientes }
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
                if coleccion == .novedades { self.limpiarNovedadesAntiguas() }
            }
        }
        listeners.append(registro)
    }

    /// Escucha el documento del propio espacio (de momento solo el candado "cerrado").
    private func escucharEspacio(_ base: DocumentReference) {
        let registro = base.addSnapshotListener { [weak self] snapshot, _ in
            let cerrado = (snapshot?.data()?["cerrado"] as? Bool) ?? false
            Task { @MainActor in
                self?.espacioCerrado = cerrado
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
    /// Primero registra este iPhone en el espacio: sin eso, las reglas no dejan leer nada.
    func consultarMiembros(codigo: String, miId: String, nombre: String) async throws -> [Miembro] {
        try await asegurarAcceso(codigo: codigo, miId: miId, nombre: nombre)
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

    func pagosDe(_ id: String) -> [PagoPareja] {
        pagos.filter { $0.escapadaId == id }.sorted { $0.fecha > $1.fecha }
    }

    func opcionesDe(_ id: String) -> [Opcion] {
        opciones.filter { $0.escapadaId == id }.sorted { $0.creadoEn < $1.creadoEn }
    }

    func aportacionesDe(hucha id: String) -> [Aportacion] {
        aportaciones.filter { $0.huchaId == id }.sorted { $0.fecha > $1.fecha }
    }

    func ahorrado(en hucha: Hucha) -> Double {
        aportaciones.filter { $0.huchaId == hucha.id }.reduce(0) { $0 + $1.importe }
    }

    /// Borra la hucha y todas sus aportaciones.
    func borrarHucha(_ hucha: Hucha) {
        guard !codigo.isEmpty else { return }
        let lote = Firestore.firestore().batch()
        for a in aportaciones where a.huchaId == hucha.id { lote.deleteDocument(referencia(.aportaciones, a.id)) }
        lote.deleteDocument(referencia(.huchas, hucha.id))
        lote.commit { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "borrar la hucha") }
            }
        }
    }

    /// Marca una opción como la elegida de su tipo (y quita la marca a las demás de ese tipo).
    func elegirOpcion(_ opcion: Opcion, elegida: Bool) {
        guard !codigo.isEmpty else { return }
        let lote = Firestore.firestore().batch()
        if elegida {
            for o in opciones where o.escapadaId == opcion.escapadaId && o.tipo == opcion.tipo && o.id != opcion.id && o.elegida {
                lote.updateData(["elegida": false], forDocument: referencia(.opciones, o.id))
            }
            anotarNovedad(icono: "✅", texto: "eligió la opción \(opcion.titulo)", escapadaId: opcion.escapadaId)
        }
        lote.updateData(["elegida": elegida], forDocument: referencia(.opciones, opcion.id))
        lote.commit { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "elegir la opción") }
            }
        }
    }

    /// Fechas especiales ordenadas por la próxima vez que tocan.
    var fechasEspecialesOrdenadas: [FechaEspecial] {
        fechasEspeciales.sorted { ($0.diasHasta() ?? Int.max) < ($1.diasHasta() ?? Int.max) }
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
    /// Si es nuevo, se apunta en "Actividad reciente" (salvo `anotar: false`).
    func guardar<T: Encodable & Identifiable>(_ valor: T, en coleccion: Coleccion, anotar: Bool = true) where T.ID == String {
        guard !codigo.isEmpty else { return }
        if anotar && !existe(valor.id, en: coleccion), let n = Almacen.describir(valor) {
            anotarNovedad(icono: n.icono, texto: n.texto, escapadaId: n.escapadaId)
        }
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

    /// Crea el documento si no existe o cambia solo esos campos si ya existe.
    func guardarCampos(_ id: String, en coleccion: Coleccion, campos: [String: Any]) {
        guard !codigo.isEmpty else { return }
        referencia(coleccion, id).setData(campos, merge: true) { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "guardar") }
            }
        }
    }

    /// Guarda el voto de una persona (1 = 👍, -1 = 👎, nil = quitar el voto) sin tocar el del otro.
    func votar(_ id: String, en coleccion: Coleccion, miId: String, valor: Int?) {
        guard !codigo.isEmpty else { return }
        let campo = FieldPath(["votos", miId])
        let nuevo: Any = valor.map { $0 as Any } ?? FieldValue.delete()
        referencia(coleccion, id).updateData([campo: nuevo]) { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "votar") }
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
        for p in pagos where p.escapadaId == escapada.id { lote.deleteDocument(referencia(.pagos, p.id)) }
        for b in billetes where b.escapadaId == escapada.id {
            lote.deleteDocument(referencia(.billetes, b.id))
            lote.deleteDocument(referencia(.billetesDatos, b.id))
        }
        for o in opciones where o.escapadaId == escapada.id { lote.deleteDocument(referencia(.opciones, o.id)) }
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
        if !reto.completado {
            anotarNovedad(icono: "📸", texto: "completó el reto «\(reto.texto)»", escapadaId: reto.escapadaId)
        }
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

    // MARK: Billetes de las reservas (misma idea que las fotos de los retos)

    func billetesDe(reserva reservaId: String) -> [Billete] {
        billetes.filter { $0.reservaId == reservaId }.sorted { $0.creadoEn < $1.creadoEn }
    }

    func guardarBillete(_ datos: Data, reservaId: String, escapadaId: String, titulo: String, miId: String) {
        guard !codigo.isEmpty else { return }
        var billete = Billete()
        billete.escapadaId = escapadaId
        billete.reservaId = reservaId
        billete.titulo = titulo
        billete.creadoPorId = miId
        billete.creadoEn = Date()
        billetesDescargados[billete.id] = datos

        let lote = Firestore.firestore().batch()
        do {
            try lote.setData(from: billete, forDocument: referencia(.billetes, billete.id))
        } catch {
            registrarFallo(error, "guardar el billete")
            return
        }
        lote.setData([
            "id": billete.id,
            "escapadaId": escapadaId,
            "datos": datos
        ], forDocument: referencia(.billetesDatos, billete.id))
        anotarNovedad(icono: "🎫", texto: "añadió un billete: \(titulo)", escapadaId: escapadaId)
        lote.commit { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "subir el billete") }
            }
        }
    }

    func borrarBillete(_ billete: Billete) {
        guard !codigo.isEmpty else { return }
        billetesDescargados[billete.id] = nil
        let lote = Firestore.firestore().batch()
        lote.deleteDocument(referencia(.billetes, billete.id))
        lote.deleteDocument(referencia(.billetesDatos, billete.id))
        lote.commit { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "borrar el billete") }
            }
        }
    }

    /// Borra un vuelo, tren o alojamiento junto con sus billetes.
    func borrarReserva(id: String, de coleccion: Coleccion) {
        guard !codigo.isEmpty else { return }
        let lote = Firestore.firestore().batch()
        for b in billetes where b.reservaId == id {
            billetesDescargados[b.id] = nil
            lote.deleteDocument(referencia(.billetes, b.id))
            lote.deleteDocument(referencia(.billetesDatos, b.id))
        }
        lote.deleteDocument(referencia(coleccion, id))
        lote.commit { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "borrar la reserva") }
            }
        }
    }

    /// Descarga la imagen de un billete si aún no está en memoria
    /// (Firestore la deja guardada en el iPhone para verla sin conexión).
    func cargarBillete(_ billete: Billete) {
        guard !codigo.isEmpty else { return }
        let clave = billete.id
        guard billetesDescargados[clave] == nil, !billetesEnDescarga.contains(clave) else { return }
        billetesEnDescarga.insert(clave)
        referencia(.billetesDatos, billete.id).getDocument { [weak self] snapshot, _ in
            let datos = snapshot?.data()?["datos"] as? Data
            Task { @MainActor in
                guard let self = self else { return }
                self.billetesEnDescarga.remove(clave)
                if let datos = datos {
                    self.billetesDescargados[clave] = datos
                }
            }
        }
    }

    /// Descarga los datos de un documento de imagen (para la copia de seguridad).
    func descargarDatos(_ coleccion: Coleccion, id: String) async -> Data? {
        guard !codigo.isEmpty else { return nil }
        let snapshot = try? await referencia(coleccion, id).getDocument()
        return snapshot?.data()?["datos"] as? Data
    }

    /// Sube una imagen tal cual (para restaurar una copia de seguridad).
    func subirDatos(_ datos: Data, a coleccion: Coleccion, id: String, escapadaId: String) {
        guard !codigo.isEmpty else { return }
        referencia(coleccion, id).setData(["id": id, "escapadaId": escapadaId, "datos": datos]) { [weak self] error in
            if let error = error {
                Task { @MainActor in self?.registrarFallo(error, "restaurar una imagen") }
            }
        }
    }

    // MARK: Actividad reciente

    /// ¿Existe ya un documento con ese ID? (para saber si un guardado es nuevo)
    func existe(_ id: String, en coleccion: Coleccion) -> Bool {
        switch coleccion {
        case .escapadas: return escapadas.contains { $0.id == id }
        case .vuelos: return vuelos.contains { $0.id == id }
        case .trenes: return trenes.contains { $0.id == id }
        case .alojamientos: return alojamientos.contains { $0.id == id }
        case .gastos: return gastos.contains { $0.id == id }
        case .checklist: return checklist.contains { $0.id == id }
        case .actividades: return actividades.contains { $0.id == id }
        case .ideas: return ideas.contains { $0.id == id }
        case .retos: return retos.contains { $0.id == id }
        case .pagos: return pagos.contains { $0.id == id }
        case .fechasEspeciales: return fechasEspeciales.contains { $0.id == id }
        case .deseos: return deseos.contains { $0.id == id }
        case .accesos: return accesos.contains { $0.id == id }
        case .novedades: return novedades.contains { $0.id == id }
        case .billetes: return billetes.contains { $0.id == id }
        case .opciones: return opciones.contains { $0.id == id }
        case .huchas: return huchas.contains { $0.id == id }
        case .aportaciones: return aportaciones.contains { $0.id == id }
        case .fotos, .billetesDatos: return false
        }
    }

    /// Texto de la novedad para cada tipo de elemento nuevo.
    static func describir(_ valor: Any) -> (icono: String, texto: String, escapadaId: String)? {
        switch valor {
        case let e as Escapada:
            return ("🗺️", "creó la escapada «\(e.titulo)»", e.id)
        case let v as Vuelo:
            return ("✈️", "añadió un vuelo \(v.origen) → \(v.destino)", v.escapadaId)
        case let t as TrenViaje:
            return ("🚂", "añadió un tren \(t.estacionOrigen) → \(t.estacionDestino)", t.escapadaId)
        case let a as Alojamiento:
            return ("🛏️", "añadió el alojamiento \(a.nombre.isEmpty ? "reservado" : a.nombre)", a.escapadaId)
        case let g as Gasto:
            return ("💶", "añadió un gasto: \(g.concepto) (\(g.importe.formatoDivisa()))", g.escapadaId)
        case let c as ItemChecklist:
            return ("🧳", "añadió a la lista: \(c.texto)", c.escapadaId)
        case let a as Actividad:
            return ("📍", "añadió un plan: \(a.nombreSitio)", a.escapadaId)
        case let i as Idea:
            return ("💡", "propuso una idea: \(i.texto)", i.escapadaId)
        case let r as Reto:
            return ("📸", "añadió un reto: \(r.texto)", r.escapadaId)
        case let p as PagoPareja:
            return ("🤝", "registró un pago de \(p.importe.formatoDivisa())", p.escapadaId)
        case let f as FechaEspecial:
            return ("💝", "añadió la fecha especial \(f.emoji) \(f.titulo)", "")
        case let d as Deseo:
            return ("⭐️", "añadió a la wishlist: \(d.titulo)", "")
        case let o as Opcion:
            let precio = o.precio > 0 ? " (\(o.precio.formatoDivisa()))" : ""
            return ("⚖️", "propuso una opción: \(o.titulo)\(precio)", o.escapadaId)
        case let h as Hucha:
            return ("🐷", "creó la hucha \(h.emoji) \(h.titulo)", "")
        case let a as Aportacion:
            if a.importe >= 0 {
                return ("🐷", "metió \(a.importe.formatoDivisa()) en la hucha", "")
            }
            return ("🐷", "sacó \((-a.importe).formatoDivisa()) de la hucha", "")
        default:
            return nil
        }
    }

    func anotarNovedad(icono: String, texto: String, escapadaId: String) {
        guard !codigo.isEmpty, !miId.isEmpty else { return }
        var n = Novedad()
        n.autorId = miId
        n.icono = icono
        n.texto = texto
        n.escapadaId = escapadaId
        n.fecha = Date()
        try? referencia(.novedades, n.id).setData(from: n)
    }

    /// Las novedades de hace más de 30 días se borran solas (una vez por sesión).
    private func limpiarNovedadesAntiguas() {
        guard !novedadesLimpiadas, !codigo.isEmpty else { return }
        novedadesLimpiadas = true
        let limite = Date().sumando(dias: -30)
        let viejas = novedades.filter { $0.fecha < limite }.prefix(400)
        guard !viejas.isEmpty else { return }
        let lote = Firestore.firestore().batch()
        for n in viejas { lote.deleteDocument(referencia(.novedades, n.id)) }
        lote.commit()
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
