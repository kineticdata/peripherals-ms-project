require 'restclient'
require 'json'
require 'rexml/document'

def get_saml_user_pass(url, username, password, to_url)
<<-SAMLUSERNAME
<?xml version="1.0" encoding="UTF-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing" xmlns:u="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
   <s:Header>
      <a:Action s:mustUnderstand="1">http://schemas.xmlsoap.org/ws/2005/02/trust/RST/Issue</a:Action>
      <a:ReplyTo>
         <a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address>
      </a:ReplyTo>
      <a:To s:mustUnderstand="1">#{to_url}</a:To>
      <o:Security xmlns:o="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" s:mustUnderstand="1">
         <o:UsernameToken>
            <o:Username>#{username}</o:Username>
            <o:Password>#{password}</o:Password>
         </o:UsernameToken>
      </o:Security>
   </s:Header>
   <s:Body>
      <t:RequestSecurityToken xmlns:t="http://schemas.xmlsoap.org/ws/2005/02/trust">
         <wsp:AppliesTo xmlns:wsp="http://schemas.xmlsoap.org/ws/2004/09/policy">
            <a:EndpointReference>
               <a:Address>#{url}</a:Address>
            </a:EndpointReference>
         </wsp:AppliesTo>
         <t:KeyType>http://schemas.xmlsoap.org/ws/2005/05/identity/NoProofKey</t:KeyType>
         <t:RequestType>http://schemas.xmlsoap.org/ws/2005/02/trust/Issue</t:RequestType>
         <t:TokenType>urn:oasis:names:tc:SAML:1.0:assertion</t:TokenType>
      </t:RequestSecurityToken>
   </s:Body>
</s:Envelope>
SAMLUSERNAME
end

def get_saml_assertion(url, assertion, to_url)
<<-SAMLASSERTION
<?xml version="1.0" encoding="UTF-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:a="http://www.w3.org/2005/08/addressing" xmlns:u="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
   <s:Header>
      <a:Action s:mustUnderstand="1">http://schemas.xmlsoap.org/ws/2005/02/trust/RST/Issue</a:Action>
      <a:ReplyTo>
         <a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address>
      </a:ReplyTo>
      <a:To s:mustUnderstand="1">#{to_url}</a:To>
      <o:Security xmlns:o="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd" s:mustUnderstand="1">#{assertion}</o:Security>
   </s:Header>
   <s:Body>
      <t:RequestSecurityToken xmlns:t="http://schemas.xmlsoap.org/ws/2005/02/trust">
         <wsp:AppliesTo xmlns:wsp="http://schemas.xmlsoap.org/ws/2004/09/policy">
            <a:EndpointReference>
               <a:Address>#{url}</a:Address>
            </a:EndpointReference>
         </wsp:AppliesTo>
         <t:KeyType>http://schemas.xmlsoap.org/ws/2005/05/identity/NoProofKey</t:KeyType>
         <t:RequestType>http://schemas.xmlsoap.org/ws/2005/02/trust/Issue</t:RequestType>
         <t:TokenType>urn:oasis:names:tc:SAML:1.0:assertion</t:TokenType>
      </t:RequestSecurityToken>
   </s:Body>
</s:Envelope>
SAMLASSERTION
end

def get_office365_cookies(sp_url, username, password, integrated_auth = false)
    if sp_url.to_s.empty?
      raise StandardError, "Invalid Url: '#{sp_url}' is not a valid Office 365 Url."
    end

    if username.to_s.empty? || password.to_s.empty?
      raise StandardError, "Invalid Username/Password: Username and/or Password cannot be left blank."
    end

    getAdfsAuthUrl = RestClient.post("https://login.microsoftonline.com/GetUserRealm.srf","handler=1&login=#{username}")
    auth_url = JSON.parse(getAdfsAuthUrl.body)["AuthURL"]

    token = {:binaryST => nil, :expires => nil}
    logon_token = nil
    body = nil
    if auth_url != nil && integrated_auth == true
        raise StandardError, "Windows Authentication not currently supported"
        # integrated_auth_url = auth_url.split("?")[0].chomp("/") + "/auth/integrated"
        # integrated_auth_url += "?" + auth_url.split("?")[1][1..-1]
        # integrated_auth_url += "&wa=wsignin1.0&wtrealm=urn:federation:MicrosoftOnline"
        # integrated_auth_url = integrated_auth_url.gsub("&username", "&username=#{username}")

        # # GetAdfsSAMLTokenWinAuth (Use a library to call ntlm)
        # resp = RestClient.get(integrated_auth) # call needs to be made using Kerberos authentication
        # doc = REXML::Document.new(resp.body)
        # Don't have a good way to test, but this is the general process if there ever is a good way to test it
        # Find doc.body
        # Find doc.form
        # Find doc => <input name="wresult"/>
        # if wresult != nil
        #   logon_token = <saml:Assertion/>.to_s
    elsif logon_token == nil && auth_url != nil && password.to_s != ""
        # hasn't been able to be tested yet
        stsUsernameMixedUrl = auth_url.split("/")[0..2].join("/") + "/adfs/services/trust/2005/usernamemixed/"
        saml_body = get_saml_user_pass("urn:federation:MicrosoftOnline", username, password, stsUsernameMixedUrl)

        begin
          resp = RestClient.post(stsUsernameMixedUrl, saml_body, :content_type => "application/soap+xml; charset=utf-8")
        rescue RestClient::InternalServerError
          raise StandardError, "Invalid Username/Password: Username/Password combination incorrect. Please check their values and try again."
        end
        doc = REXML::Document.new(resp.body)
        logon_token = REXML::XPath.first(doc, "/s:Envelope/s:Body/t:RequestSecurityTokenResponse/t:RequestedSecurityToken/saml:Assertion").to_s
        if logon_token != nil
            body = get_saml_assertion(sp_url, logon_token, "https://login.microsoftonline.com/extSTS.srf")
        end
    elsif logon_token == nil && auth_url == nil && password.to_s != ""
        body = get_saml_user_pass(sp_url, username, password, "https://login.microsoftonline.com/extSTS.srf")
    end

    if body != nil
        resp = RestClient.post("https://login.microsoftonline.com/extSTS.srf", body, :content_type => "application/soap+xml; charset=utf-8")
        doc = REXML::Document.new(resp.body)
        binaryST = REXML::XPath.first(doc, "/S:Envelope/S:Body/wst:RequestSecurityTokenResponse/wst:RequestedSecurityToken/wsse:BinarySecurityToken")
        expires = REXML::XPath.first(doc, "/S:Envelope/S:Body/wst:RequestSecurityTokenResponse/wst:Lifetime/wsu:Expires")
        if !binaryST.nil?
          token[:binaryST] = binaryST.text
          token[:expires] = expires.text
        end
    end

    if token[:binaryST].nil?
      raise StandardError, "The Office 365 Url and Username/Password combination do not match. Please check the Office 365 Url and try again."
    end

    ws_signin_url = sp_url.split("/")[0..2].join("/") + "/_forms/default.aspx?wa=wsignin1.0"
    resp = nil
    cookies = []
    begin
        resp = RestClient.post(ws_signin_url, token[:binaryST])
    rescue RestClient::Found => redirect
        cookies = redirect.response.headers[:set_cookie]
    rescue SocketError => error 
        raise StandardError, "Invalid Url: The url '#{sp_url}' is not a valid Office 365 Url."
    end

    return cookies.join(";")
end