package com.kineticdata.bridgehub.adapter.msproject;

import com.kineticdata.bridgehub.adapter.BridgeAdapter;
import com.kineticdata.bridgehub.adapter.BridgeError;
import com.kineticdata.bridgehub.adapter.BridgeRequest;
import com.kineticdata.bridgehub.adapter.BridgeUtils;
import com.kineticdata.bridgehub.adapter.Count;
import com.kineticdata.bridgehub.adapter.Record;
import com.kineticdata.bridgehub.adapter.RecordList;
import com.kineticdata.commons.v1.config.ConfigurableProperty;
import com.kineticdata.commons.v1.config.ConfigurablePropertyMap;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.StringWriter;
import java.io.UnsupportedEncodingException;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.parsers.ParserConfigurationException;
import javax.xml.transform.OutputKeys;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerException;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;
import org.apache.http.Header;
import org.apache.http.HttpEntity;
import org.apache.http.HttpResponse;
import org.apache.http.client.HttpClient;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.util.EntityUtils;
import org.json.simple.JSONArray;
import org.json.simple.JSONObject;
import org.json.simple.JSONValue;
import org.slf4j.LoggerFactory;
import org.w3c.dom.Document;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;
import org.xml.sax.SAXException;


public class MSProjectAdapter implements BridgeAdapter {
    /*----------------------------------------------------------------------------------------------
     * PROPERTIES
     *--------------------------------------------------------------------------------------------*/

    /** Defines the adapter display name */
    public static final String NAME = "MSProject Bridge";

    /** Defines the logger */
    private static final org.slf4j.Logger logger = LoggerFactory.getLogger(MSProjectAdapter.class);

    /** Adapter version constant. */
    public static String VERSION;
    /** Load the properties version from the version.properties file. */
    static {
        try {
            java.util.Properties properties = new java.util.Properties();
            properties.load(MSProjectAdapter.class.getResourceAsStream("/"+MSProjectAdapter.class.getName()+".version"));
            VERSION = properties.getProperty("version");
        } catch (IOException e) {
            logger.warn("Unable to load "+MSProjectAdapter.class.getName()+" version properties.", e);
            VERSION = "Unknown";
        }
    }

    /** Defines the collection of property names for the adapter */
    public static class Properties {
        public static final String PROPERTY_USERNAME = "Username";
        public static final String PROPERTY_PASSWORD = "Password";
        public static final String PROPERTY_HOMEPAGE_URL = "Homepage Url";
    }

    private final ConfigurablePropertyMap properties = new ConfigurablePropertyMap(
        new ConfigurableProperty(MSProjectAdapter.Properties.PROPERTY_USERNAME).setIsRequired(true),
        new ConfigurableProperty(MSProjectAdapter.Properties.PROPERTY_PASSWORD).setIsRequired(true).setIsSensitive(true),
        new ConfigurableProperty(MSProjectAdapter.Properties.PROPERTY_HOMEPAGE_URL).setIsRequired(true)
    );

    /**
     * Structures that are valid to use in the bridge
     */
    public static final List<String> VALID_STRUCTURES = Arrays.asList(new String[] {
        "Projects"
    });

    private String username;
    private String password;
    private String homepageUrl;

    /*---------------------------------------------------------------------------------------------
     * SETUP METHODS
     *-------------------------------------------------------------------------------------------*/

    @Override
    public void initialize() throws BridgeError {
        this.username = properties.getValue(Properties.PROPERTY_USERNAME);
        this.password = properties.getValue(Properties.PROPERTY_PASSWORD);
        this.homepageUrl = properties.getValue(Properties.PROPERTY_HOMEPAGE_URL);
        testAuth();
    }

    @Override
    public String getName() {
        return NAME;
    }

    @Override
    public String getVersion() {
        return VERSION;
    }

    @Override
    public void setProperties(Map<String,String> parameters) {
        properties.setValues(parameters);
    }

    @Override
    public ConfigurablePropertyMap getProperties() {
        return properties;
    }

    /*---------------------------------------------------------------------------------------------
     * IMPLEMENTATION METHODS
     *-------------------------------------------------------------------------------------------*/

    @Override
    public Count count(BridgeRequest request) throws BridgeError {
        String structure = request.getStructure();

        if (!VALID_STRUCTURES.contains(structure)) {
            throw new BridgeError("Invalid Structure: '" + request.getStructure() + "' is not a valid structure");
        }

        MSProjectQualificationParser parser = new MSProjectQualificationParser();
        StringBuilder queryBuilder = new StringBuilder();
        queryBuilder.append(String.format("%s/_api/ProjectData/Projects?", this.homepageUrl));
        String query = parser.parse(request.getQuery(),request.getParameters());

        if (query != null){
            queryBuilder.append(URLEncoder.encode(query));
        }

        // We have to replace the encoded "&" and "=" values because the Sharepoint API
        // expects the literal values, not the encoded version.
        String url = queryBuilder.toString().replaceAll("%3D", "=").replaceAll("%26", "&");

        String cookies = get_office365_cookies(String.format("%s/_api/ProjectData/Projects?", this.homepageUrl), this.username, this.password, false);

        HttpClient client = HttpClients.createDefault();
        HttpGet get = new HttpGet(url);
        get.setHeader("cookie", cookies);
        get.setHeader("Accept", "application/json");

        HttpResponse response;
        String output = "";

        try {
            response = client.execute(get);
            HttpEntity entity = response.getEntity();
            output = EntityUtils.toString(entity);
        }
        catch (IOException e) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Microsoft Project");
        }

        Long count;
        JSONObject jsonOutput = (JSONObject)JSONValue.parse(output);

        if (jsonOutput.get("odata.error") != null) {
            JSONObject error = (JSONObject)jsonOutput.get("odata.error");
            JSONObject errorMessage = (JSONObject) error.get("message");
            logger.error("Error: " + errorMessage.get("value"));
            throw new BridgeError((String)errorMessage.get("value"));
        }

        JSONArray results = (JSONArray)jsonOutput.get("value");
        count = Long.valueOf(results.size());

        return new Count(count);
    }

    @Override
    public Record retrieve(BridgeRequest request) throws BridgeError {
        List<String> fields = request.getFields();
        String structure = request.getStructure();

        if (!VALID_STRUCTURES.contains(structure)) {
            throw new BridgeError("Invalid Structure: '" + request.getStructure() + "' is not a valid structure");
        }

        MSProjectQualificationParser parser = new MSProjectQualificationParser();
        StringBuilder queryBuilder = new StringBuilder();
        queryBuilder.append(String.format("%s/_api/ProjectData/Projects?", this.homepageUrl));
        String query = parser.parse(request.getQuery(),request.getParameters());

        if (query != null){
            queryBuilder.append(URLEncoder.encode(query));
        }

        // We have to replace the encoded "&" and "=" values because the Sharepoint API
        // expects the literal values, not the encoded version.
        String url = queryBuilder.toString().replaceAll("%3D", "=").replaceAll("%26", "&");

        String cookies = get_office365_cookies(String.format("%s/_api/ProjectData/Projects?", this.homepageUrl), this.username, this.password, false);

        HttpClient client = HttpClients.createDefault();
        HttpGet get = new HttpGet(url);
        get.setHeader("cookie", cookies);
        get.setHeader("Accept", "application/json");

        HttpResponse response;
        String output = "";

        try {
            response = client.execute(get);
            HttpEntity entity = response.getEntity();
            output = EntityUtils.toString(entity);
        }
        catch (IOException e) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Microsoft Project");
        }

        JSONObject jsonOutput = (JSONObject)JSONValue.parse(output);

        if (jsonOutput.get("odata.error") != null) {
            JSONObject error = (JSONObject)jsonOutput.get("odata.error");
            JSONObject errorMessage = (JSONObject) error.get("message");
            logger.error("Error: " + errorMessage.get("value"));
            throw new BridgeError((String)errorMessage.get("value"));
        }

        JSONArray results = (JSONArray)jsonOutput.get("value");
        Record record;

        if (results.size() > 1) {
            throw new BridgeError("Multiple results matched an expected single match query");
        }
        else if (results.isEmpty()) {
            record = new Record(null);
        }
        else {
            if (fields == null) {
                record = new Record(null);
            } else {
                JSONObject result = (JSONObject)results.get(0);
                Map<String,Object> recordMap = new LinkedHashMap<String,Object>();
                for (String field : fields) {
                    recordMap.put(field, result.get(field));
                }
                record = new Record(recordMap);
            }
        }

        return record;
    }

    @Override
    public RecordList search(BridgeRequest request) throws BridgeError {
        List<String> fields = request.getFields();
        String structure = request.getStructure();

        if (!VALID_STRUCTURES.contains(structure)) {
            throw new BridgeError("Invalid Structure: '" + request.getStructure() + "' is not a valid structure");
        }

        MSProjectQualificationParser parser = new MSProjectQualificationParser();
        StringBuilder queryBuilder = new StringBuilder();
        Map<String,String> metadata = BridgeUtils.normalizePaginationMetadata(request.getMetadata());
        queryBuilder.append(String.format("%s/_api/ProjectData/Projects?", this.homepageUrl));
        String query = parser.parse(request.getQuery(),request.getParameters());

        if (query != null){
            queryBuilder.append(URLEncoder.encode(query));
        }

        // We have to replace the encoded "&" and "=" values because the Sharepoint API
        // expects the literal values, not the encoded version.
        String url = queryBuilder.toString().replaceAll("%3D", "=").replaceAll("%26", "&");

        String cookies = get_office365_cookies(String.format("%s/_api/ProjectData/Projects?", this.homepageUrl), this.username, this.password, false);

        HttpClient client = HttpClients.createDefault();
        HttpGet get = new HttpGet(url);
        get.setHeader("cookie", cookies);
        get.setHeader("Accept", "application/json");

        HttpResponse response;
        String output = "";

        try {
            response = client.execute(get);
            HttpEntity entity = response.getEntity();
            output = EntityUtils.toString(entity);
        }
        catch (IOException e) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Microsoft Project");
        }

        JSONObject jsonOutput = (JSONObject)JSONValue.parse(output);

        if (jsonOutput.get("odata.error") != null) {
            JSONObject error = (JSONObject)jsonOutput.get("odata.error");
            JSONObject errorMessage = (JSONObject) error.get("message");
            logger.error("Error: " + errorMessage.get("value"));
            throw new BridgeError((String)errorMessage.get("value"));
        }

        JSONArray results = (JSONArray)jsonOutput.get("value");

        List<Record> records = new ArrayList<Record>();

        for (int i=0; i < results.size(); i++) {
            JSONObject recordObject = (JSONObject)results.get(i);
            records.add(new Record((Map<String,Object>)recordObject));
        }

        // If fields is null, all fields are returned. Get the first element
        // of the returned objects and get its fields.
        if (fields == null ) {
            fields = new ArrayList<String>();
            JSONObject firstObject = (JSONObject)results.get(0);
            Iterator allFields = firstObject.entrySet().iterator();
            while ( allFields.hasNext() ) {
                Map.Entry pair = (Map.Entry)allFields.next();
                fields.add(pair.getKey().toString());
            }
        }

        metadata.put("count",String.valueOf(records.size()));
        metadata.put("size", String.valueOf(records.size()));

        // Returning the response
        return new RecordList(fields, records, metadata);
    }

    /*----------------------------------------------------------------------------------------------
     * PRIVATE HELPER METHODS
     *--------------------------------------------------------------------------------------------*/

    private void testAuth() throws BridgeError {
        logger.debug("Testing the authentication credentials");
        StringBuilder queryBuilder = new StringBuilder();
        queryBuilder.append(String.format("%s/_api/ProjectData/Projects?$top=1", this.homepageUrl));

        String cookies = get_office365_cookies(String.format("%s/_api/ProjectData/Projects?", this.homepageUrl), this.username, this.password, false);

        HttpClient client = HttpClients.createDefault();
        HttpGet get = new HttpGet(queryBuilder.toString());
        get.setHeader("cookie", cookies);
        get.setHeader("Accept", "application/json");

        HttpResponse response;

        try {
            response = client.execute(get);
            HttpEntity entity = response.getEntity();
            EntityUtils.consume(entity);
            if (response.getStatusLine().getStatusCode() == 401) {
                throw new BridgeError("Unauthorized: The inputted Username/Password combination is not valid.");
            }
        }
        catch (IOException e) {
            logger.error(e.getMessage());
            throw new BridgeError("Unable to make a connection to properly to Microsoft Project.");
        }
    }

    /**
     * A method used to authenticate using an external application (in command line)
     */
    private String get_saml_user_pass(String url, String username, String password, String to_url) throws BridgeError {
        StringBuilder samlUsername = new StringBuilder();
        samlUsername.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
        samlUsername.append("<s:Envelope xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\" xmlns:a=\"http://www.w3.org/2005/08/addressing\" xmlns:u=\"http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd\">");
        samlUsername.append("<s:Header>");
        samlUsername.append("<a:Action s:mustUnderstand=\"1\">http://schemas.xmlsoap.org/ws/2005/02/trust/RST/Issue</a:Action>");
        samlUsername.append("<a:ReplyTo>");
        samlUsername.append("<a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address>");
        samlUsername.append("</a:ReplyTo>");
        samlUsername.append(String.format("<a:To s:mustUnderstand=\"1\">%s</a:To>", to_url));
        samlUsername.append("<o:Security xmlns:o=\"http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd\" s:mustUnderstand=\"1\">");
        samlUsername.append("<o:UsernameToken>");
        samlUsername.append(String.format("<o:Username>%s</o:Username>", username));
        samlUsername.append(String.format("<o:Password>%s</o:Password>", password));
        samlUsername.append("</o:UsernameToken>");
        samlUsername.append("</o:Security>");
        samlUsername.append("</s:Header>");
        samlUsername.append("<s:Body>");
        samlUsername.append("<t:RequestSecurityToken xmlns:t=\"http://schemas.xmlsoap.org/ws/2005/02/trust\">");
        samlUsername.append("<wsp:AppliesTo xmlns:wsp=\"http://schemas.xmlsoap.org/ws/2004/09/policy\">");
        samlUsername.append("<a:EndpointReference>");
        samlUsername.append(String.format("<a:Address>%s</a:Address>", url));
        samlUsername.append("</a:EndpointReference>");
        samlUsername.append("</wsp:AppliesTo>");
        samlUsername.append("<t:KeyType>http://schemas.xmlsoap.org/ws/2005/05/identity/NoProofKey</t:KeyType>");
        samlUsername.append("<t:RequestType>http://schemas.xmlsoap.org/ws/2005/02/trust/Issue</t:RequestType>");
        samlUsername.append("<t:TokenType>urn:oasis:names:tc:SAML:1.0:assertion</t:TokenType>");
        samlUsername.append("</t:RequestSecurityToken>");
        samlUsername.append("</s:Body>");
        samlUsername.append("</s:Envelope>");
        return samlUsername.toString();
    }

    private String get_saml_assertion(String url, String assertion, String to_url) throws BridgeError {
        StringBuilder samlAssertion = new StringBuilder();
        samlAssertion.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
        samlAssertion.append("<s:Envelope xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\" xmlns:a=\"http://www.w3.org/2005/08/addressing\" xmlns:u=\"http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd\">");
        samlAssertion.append("<s:Header>");
        samlAssertion.append("<a:Action s:mustUnderstand=\"1\">http://schemas.xmlsoap.org/ws/2005/02/trust/RST/Issue</a:Action>");
        samlAssertion.append("<a:ReplyTo>");
        samlAssertion.append("<a:Address>http://www.w3.org/2005/08/addressing/anonymous</a:Address>");
        samlAssertion.append("</a:ReplyTo>");
        samlAssertion.append(String.format("<a:To s:mustUnderstand=\"1\">%s</a:To>", to_url));
        samlAssertion.append(String.format("<o:Security xmlns:o=\"http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd\" s:mustUnderstand=\"1\">%s</o:Security>", assertion));
        samlAssertion.append("</s:Header>");
        samlAssertion.append("<s:Body>");
        samlAssertion.append("<t:RequestSecurityToken xmlns:t=\"http://schemas.xmlsoap.org/ws/2005/02/trust\">");
        samlAssertion.append("<wsp:AppliesTo xmlns:wsp=\"http://schemas.xmlsoap.org/ws/2004/09/policy\">");
        samlAssertion.append("<a:EndpointReference>");
        samlAssertion.append(String.format("<a:Address>%s</a:Address>", url));
        samlAssertion.append("</a:EndpointReference>");
        samlAssertion.append("</wsp:AppliesTo>");
        samlAssertion.append("<t:KeyType>http://schemas.xmlsoap.org/ws/2005/05/identity/NoProofKey</t:KeyType>");
        samlAssertion.append("<t:RequestType>http://schemas.xmlsoap.org/ws/2005/02/trust/Issue</t:RequestType>");
        samlAssertion.append("<t:TokenType>urn:oasis:names:tc:SAML:1.0:assertion</t:TokenType>");
        samlAssertion.append("</t:RequestSecurityToken>");
        samlAssertion.append("</s:Body>");
        samlAssertion.append("</s:Envelope>");
        return samlAssertion.toString();
    }

    private String get_office365_cookies(String sp_url, String username, String password, Boolean integratedAuth) throws BridgeError {
        if (sp_url.isEmpty()){
            throw new BridgeError("Invalid Url:" + sp_url + "is not a valid Office 365 Url.");
        }

        if (username.isEmpty() || password.isEmpty()){
            throw new BridgeError("Invalid Username/Password: Username and/or Password cannot be left blank.");
        }

        HttpClient client = HttpClients.createDefault();
        String url = String.format("https://login.microsoftonline.com/GetUserRealm.srf?handler=1&login=%s", username);
        HttpPost post  = new HttpPost(url);
        HttpResponse response;
        String output = "";
        String cookie = "";

        try {
            response = client.execute(post);
            HttpEntity entity = response.getEntity();
            output = EntityUtils.toString(entity);
        }
        catch (IOException e) {
            throw new BridgeError("Unable to make a connection to properly execute the query to Microsoft Project");
        }

        JSONObject jsonOutput = (JSONObject)JSONValue.parse(output);
        String authUrl = (String) jsonOutput.get("AuthURL");

        Map<String, String> token = new HashMap<String,String>();
        token.put("binaryST", null);
        token.put("expires", null);
        String logonToken = null;
        String body = null;

        if (authUrl != null && integratedAuth == true){
            throw new BridgeError("Windows Authentication not currently supported.");
        } else if (logonToken == null && authUrl != null && !password.isEmpty()){
            String[] strArr = authUrl.split("/");
            String stsUsernameMixedUrl = strArr[0] + "//" + strArr[1] + strArr[2] + "/adfs/services/trust/2005/usernamemixed/";
            String saml_body = get_saml_user_pass("urn:federation:MicrosoftOnline", username, password, stsUsernameMixedUrl);
            StringEntity entity;
            try {
                entity = new StringEntity(saml_body);
            } catch (UnsupportedEncodingException ex) {
                throw new BridgeError("Unable to make a connection to properly execute the query to Microsoft Project");
            }

            HttpClient usernameClient = HttpClients.createDefault();
            HttpPost usernamePost = new HttpPost(stsUsernameMixedUrl);
            usernamePost.setEntity(entity);
            usernamePost.setHeader("Content-Type", "application/soap+xml");
            HttpResponse usernameResponse;
            String usernameOutput;

            try {
                usernameResponse = usernameClient.execute(usernamePost);
                HttpEntity usernameEntity = usernameResponse.getEntity();
                usernameOutput = EntityUtils.toString(usernameEntity);

                Document doc;
                Node node;
                try {
                    DocumentBuilderFactory dbFactory = DocumentBuilderFactory.newInstance();
                    DocumentBuilder dBuilder = dbFactory.newDocumentBuilder();
                    doc = dBuilder.parse(new InputSource(new ByteArrayInputStream(usernameOutput.getBytes("utf-8"))));
                    doc.getDocumentElement().normalize();
                    node = doc.getElementsByTagName("saml:Assertion").item(0);
                }
                catch (Exception e) {
                    logger.error("Full XML Error: " + e.getMessage());
                    throw new BridgeError("Parsing of the XML response failed",e);
                }

                TransformerFactory tf = TransformerFactory.newInstance();
                Transformer transformer = tf.newTransformer();
                transformer.setOutputProperty(OutputKeys.OMIT_XML_DECLARATION, "yes");
                StringWriter writer = new StringWriter();
                transformer.transform(new DOMSource(node), new StreamResult(writer));
                String logon_token = writer.getBuffer().toString().replaceAll("\n|\r", "");

                if (logon_token != null) {
                    body = get_saml_assertion(sp_url, logon_token, "https://login.microsoftonline.com/extSTS.srf");
                }

                if (body != null) {
                    HttpClient tokenClient = HttpClients.createDefault();
                    HttpPost tokenPost = new HttpPost("https://login.microsoftonline.com/extSTS.srf");

                    StringEntity tokenEntity;
                    try {
                        tokenEntity = new StringEntity(body);
                    } catch (UnsupportedEncodingException ex) {
                        throw new BridgeError("Unable to make a connection to properly execute the query to Microsoft Project");
                    }

                    tokenPost.setEntity(tokenEntity);
                    tokenPost.setHeader("Content-Type", "application/soap+xml");
                    HttpResponse tokenResponse;
                    String tokenOutput;

                    tokenResponse = tokenClient.execute(tokenPost);
                    HttpEntity httpTokenEntity = tokenResponse.getEntity();
                    tokenOutput = EntityUtils.toString(httpTokenEntity);

                    Document tokenDoc;

                    try {
                        DocumentBuilderFactory dbFactory = DocumentBuilderFactory.newInstance();
                        DocumentBuilder dBuilder = dbFactory.newDocumentBuilder();
                        tokenDoc = dBuilder.parse(new InputSource(new ByteArrayInputStream(tokenOutput.getBytes("utf-8"))));
                        tokenDoc.getDocumentElement().normalize();
                        NodeList binary = tokenDoc.getElementsByTagName("wsse:BinarySecurityToken");
                        NodeList expireDate = tokenDoc.getElementsByTagName("wsu:Expires");
                        String binaryST = binary.item(0).getTextContent();
                        String expires = expireDate.item(0).getTextContent();

                        if (binaryST != null){
                            token.put("binaryST", binaryST);
                            token.put("expires", expires);
                        }
                    }
                    catch (Exception e) {
                        logger.error("Full XML Error: " + e.getMessage());
                        throw new BridgeError("Parsing of the XML response failed",e);
                    }
                }

                if (token.get("binaryST") == null) {
                    throw new BridgeError("The Office 365 Url and Username/Password combination do not match. Please check the Office 365 Url and try again.");
                }

                String []signin_url = sp_url.split("/");
                String ws_signin_url = signin_url[0] + "//" + signin_url[1] + signin_url[2] + "/_forms/default.aspx?wa=wsignin1.0";

                HttpClient cookiesClient = HttpClients.createDefault();
                HttpPost cookiesPost = new HttpPost(ws_signin_url);
                StringEntity cookiesEntity;

                try {
                    cookiesEntity = new StringEntity(token.get("binaryST"));
                } catch (UnsupportedEncodingException ex) {
                    throw new BridgeError("Unable to make a connection to properly execute the query to Microsoft Project");
                }

                cookiesPost.setEntity(cookiesEntity);
                HttpResponse cookiesResponse;
                cookiesResponse = cookiesClient.execute(cookiesPost);
                Header headers[] = cookiesResponse.getAllHeaders();
                ArrayList<String> cookies = new ArrayList<String>();
                for(Header h : headers){
                    if (h.getName().equals("Set-Cookie")){
                        cookies.add(h.getValue());
                    }
		}

                cookie = String.format(cookies.get(0) + ";" + cookies.get(1) + cookies.get(2));
            }
            catch (IOException e) {
                throw new BridgeError("Unable to make a connection to properly execute the query to Microsoft Project");
            } catch (TransformerException e) {
                throw new BridgeError("Unable to make a connection to properly execute the query to Microsoft Project");
            }
        }

        return cookie;
    }
}
