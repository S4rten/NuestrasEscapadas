import Foundation
import SwiftUI

/// Identidad de ESTE iPhone: ID único (se crea una vez y no cambia),
/// nombre de la persona y código del espacio compartido de la pareja.
@MainActor
final class Sesion: ObservableObject {
    private enum Clave {
        static let id = "escapadas_mi_id_v2"
        static let nombre = "escapadas_mi_nombre_v2"
        static let codigo = "escapadas_codigo_v2"
    }

    @Published private(set) var miId: String
    @Published private(set) var miNombre: String
    @Published private(set) var codigo: String

    var estaConfigurada: Bool {
        !miNombre.recortado.isEmpty && Sesion.codigoValido(codigo)
    }

    init() {
        let d = UserDefaults.standard
        if let guardado = d.string(forKey: Clave.id), !guardado.isEmpty {
            miId = guardado
        } else {
            let nuevo = nuevoId()
            d.set(nuevo, forKey: Clave.id)
            miId = nuevo
        }
        miNombre = d.string(forKey: Clave.nombre) ?? ""
        codigo = d.string(forKey: Clave.codigo) ?? ""
    }

    /// Entra en un espacio. Si `id` viene informado, este iPhone adopta ese ID
    /// (sirve para recuperar tu identidad si reinstalas la app).
    func entrar(nombre: String, codigo: String, id: String? = nil) {
        let d = UserDefaults.standard
        if let id = id, !id.isEmpty {
            miId = id
            d.set(id, forKey: Clave.id)
        }
        miNombre = nombre.recortado
        self.codigo = Sesion.normalizar(codigo)
        d.set(miNombre, forKey: Clave.nombre)
        d.set(self.codigo, forKey: Clave.codigo)
    }

    func cambiarNombre(_ nuevo: String) {
        let limpio = nuevo.recortado
        guard !limpio.isEmpty else { return }
        miNombre = limpio
        UserDefaults.standard.set(limpio, forKey: Clave.nombre)
    }

    /// Sale del espacio (mantiene el ID y el nombre de este iPhone).
    func salir() {
        codigo = ""
        UserDefaults.standard.removeObject(forKey: Clave.codigo)
    }

    // MARK: Códigos de espacio

    nonisolated static func normalizar(_ texto: String) -> String {
        let permitidos = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        let mayusculas = texto.recortado.uppercased().replacingOccurrences(of: " ", with: "-")
        return String(mayusculas.filter { permitidos.contains($0) })
    }

    nonisolated static func codigoValido(_ codigo: String) -> Bool {
        codigo.count >= 12
    }

    /// Código largo y aleatorio, por ejemplo "K7QM-X2PD-9TRW" (sin letras que se confunden).
    nonisolated static func generarCodigo() -> String {
        let alfabeto = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var grupos: [String] = []
        for _ in 0..<3 {
            var grupo = ""
            for _ in 0..<4 {
                grupo.append(alfabeto.randomElement() ?? "X")
            }
            grupos.append(grupo)
        }
        return grupos.joined(separator: "-")
    }
}
