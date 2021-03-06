import Foundation
import Vapor
import AuthProvider
import HTTP
import Flash
import Validation

public final class LoginController {
    
    public let drop: Droplet
    
    public init(droplet: Droplet) {
        drop = droplet
    }
    
    
    /// Landing
    ///
    /// - Parameter request: Request
    /// - Returns: Response
    public func landing(request: Request) -> Response {
        do {
            guard let user: BackendUser = request.auth.authenticated() else {
                throw Abort(
                    .forbidden,
                    metadata: nil,
                    reason: "Forbidden"
                )
            }
            
            return Response(redirect: "/admin/dashboard").flash(.success, "Logged in as \(user.email)")
        } catch {
            return Response(redirect: "/admin/login").flash(.error, "Please login")
        }
    }
    
    
    /// Reset password form
    ///
    /// - Parameter request: Request
    /// - Returns: View
    /// - Throws: Error
    public func resetPasswordForm(request: Request) throws -> View {
        return try drop.view.make("Login/reset", for: request)
    }
    
    
    /// Reset password submit
    ///
    /// It's on purpose that we show a success message if user is not found. Else this action could be used to find emails in db
    ///
    /// - Parameter request: Request
    /// - Returns: Response
    public func resetPasswordSubmit(request: Request) -> Response {
        do {
            guard let email = request.data["email"]?.string, let backendUser: BackendUser = try BackendUser.makeQuery().filter("email", email).first() else {
                return Response(redirect: "/admin/login").flash(.success, "E-mail with instructions sent if user exists")
            }
        
            try BackendUserResetPasswordToken.makeQuery().filter("email", email).delete()
            
            // Make a token
            let token = BackendUserResetPasswordToken(email: email)
            try token.save()
            
            // Send mail
            try Mailer.sendResetPasswordMail(drop: drop, backendUser: backendUser, token: token)
            
            return Response(redirect: "/admin/login").flash(.success, "E-mail with instructions sent if user exists")
        } catch {
            return Response(redirect: "/admin/login/reset").flash(.error, "Error occurred")
        }
    }
    
    
    /// Reset password token form
    ///
    /// - Parameter request: Request
    /// - Returns: View
    /// - Throws: Various Abort.customs
    public func resetPasswordTokenForm(request: Request) throws -> View {
        guard let tokenStr = request.parameters["token"]?.string else {
            throw Abort(
                .badRequest,
                metadata: nil,
                reason: "Missing token"
            )
        }
        
        // If token does not exist or cannot be used is the same error
        guard let token = try BackendUserResetPasswordToken.makeQuery().filter("token", tokenStr).first(), !token.canBeUsed() else {
            throw Abort(
                .badRequest,
                metadata: nil,
                reason: "Token is invalid"
            )
        }
        
        return try drop.view.make("ResetPassword/form", [
            "token": token
        ], for: request)
    }
    
    
    /// Reset password token submit, check token and make sure new password is matching requirement
    ///
    /// - Parameter request: Request
    /// - Returns: Response
    /// - Throws: Varius Abort.customs
    public func resetPasswordTokenSubmit(request: Request) throws -> Response {
        guard let tokenStr = request.data["token"]?.string, let email = request.data["email"]?.string,
            let password = request.data["password"]?.string, let passwordRepeat = request.data["password_repeat"]?.string else {
                throw Abort.badRequest
        }
        
        guard let token = try BackendUserResetPasswordToken.makeQuery().filter("token", tokenStr).first(), !token.canBeUsed() else {
            throw Abort(
                .badRequest,
                metadata: nil,
                reason: "Token does not exist"
            )
        }
        
        if token.email != email {
            throw Abort(
                .badRequest,
                metadata: nil,
                reason: "Token does not match email"
            )
        }
        
        if(password != passwordRepeat) {
            return Response(redirect: "/admin/login/reset/" + tokenStr).flash(.error, "Passwords did not match")
        }
        
        if !password.passes(Count.min(8)) {
            return Response(redirect: "/admin/login/reset/" + tokenStr).flash(.error, "Passwords did not match requirement")
        }
        
        guard let backendUser = try BackendUser.makeQuery().filter("email", email).first() else {
            throw Abort(
                .badRequest,
                metadata: nil,
                reason: "User was not found"
            )
        }
        
        // Set usedAt & save
        token.usedAt = Date()
        try token.save()
        
        // Set new password & save
        try backendUser.setPassword(password)
        try backendUser.save()
        
        return Response(redirect: "/admin/login").flash(.success, "Password is reset")
    }
    
    /// Login form
    ///l    /// - Parameter request: Request
    /// - Returns: View
    /// - Throws: Error
    public func form(request: Request) throws -> View {

        return try drop.view.make(
            "Login/login",
            ["next": request.query?["next"] ?? nil],
            for: request
        )
    }
    
    
    /// Submit login
    ///
    /// - Parameter request: Request
    /// - Returns: Response
    /// - Throws: Error
    public func submit(request: Request) throws -> Response {
        
        // Guard credentials
        guard let username = request.data["email"]?.string, let password = request.data["password"]?.string else {
            throw Abort(
                .badRequest,
                metadata: nil,
                reason: "Missing username or password"
            )
        }
        
        do {
            // TODO REMEMBER
            //let remember: Bool = request.data["remember"]?.bool ?? false
            let user = try BackendUser.authenticate(Password(username: username, password: password))
            request.auth.authenticate(user)
            
            // Generate redirect path
            var redirect = "/admin/dashboard"
            if let next: String = request.query?["next"]?.string, !next.isEmpty {
                redirect = next
            }
        
            return Response(redirect: redirect).flash(.success, "Logged in as \(username)")
        } catch {
            return Response(redirect: "/admin/login").flash(.error, "Failed to login")
        }
    }
    
    /// SSO login
    ///
    /// - Parameter request: request
    /// - Returns: return response
    /// - Throws: throws Abort.custom internalServerError for missing config or sso
    public func sso(request: Request) throws -> ResponseRepresentable {
        guard let config: Configuration = drop.storage["adminPanelConfig"] as? Configuration else {
            throw Abort(
                .internalServerError,
                metadata: nil,
                reason: "AdminPanel missing configuration"
            )
        }
        
        guard let ssoProvider: SSOProtocol = config.ssoProvider else {
            throw Abort(
                .internalServerError,
                metadata: nil,
                reason: "AdminPanel no SSO setup"
            )
        }
        
        return try ssoProvider.auth(request)
    }
    
    /// SSO callback
    ///
    /// - Parameter request: request
    /// - Returns: return response
    /// - Throws: throws Abort.custom internalServerError for missing config or sso
    public func ssoCallback(request: Request) throws -> ResponseRepresentable {
        guard let config: Configuration = drop.storage["adminPanelConfig"] as? Configuration else {
            throw Abort(
                .internalServerError,
                metadata: nil,
                reason: "AdminPanel missing configuration"
            )
        }
        
        guard let ssoProvider: SSOProtocol = config.ssoProvider else {
            throw Abort(
                .internalServerError,
                metadata: nil,
                reason: "AdminPanel no SSO setup"
            )
        }
        
        return try ssoProvider.callback(request)
    }
}
