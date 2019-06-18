# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))
# Require the Office 365 Authentication file
require File.expand_path(File.join(File.dirname(__FILE__), 'o365_authentication'))

class MsprojectProjectCreateV1
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)

    # Store the info values in a Hash of info names to values.
    @info_values = {}
    REXML::XPath.each(@input_document,"/handler/infos/info") { |item|
      @info_values[item.attributes['name']] = item.text
    }
    @enable_debug_logging = @info_values['enable_debug_logging'] == 'Yes'

    # Store parameters values in a Hash of parameter names to values.
    @parameters = {}
    REXML::XPath.match(@input_document, '/handler/parameters/parameter').each do |node|
      @parameters[node.attribute('name').value] = node.text.to_s
    end
  end

  def execute()
    # Retrieve the cookies
    cookies = get_office365_cookies(@info_values['ms_project_location'],@info_values['username'],@info_values['password'])

    proj_resource = RestClient::Resource.new(@info_values['ms_project_location'].chomp("/"),
      :headers => {:content_type => "application/json",:accept => "application/json", :cookie => cookies})
    
    context_endpoint = proj_resource["/_api/contextinfo"]
    puts "Sending a request to get the FormDigestValue that will be passed at the X-RequestDigest header in the create call" if @enable_debug_logging
    begin
      results = context_endpoint.post ""
    rescue RestClient::Exception => error
      raise StandardError, error.inspect
    end

    json = JSON.parse(results)
    # Get the JSON value array that contains the lookup table information
    form_digest_value = json["FormDigestValue"]
    proj_resource.headers["X-RequestDigest"] = form_digest_value

    # Post the new project using the enterprise project id and the name
    # Return the internal project id
    create_params = {
      "odata.type" => "PS.PublishedProject",
      "EnterpriseProjectTypeId" => @parameters['enterprise_project_type'],
      "Name" => @parameters['name']
    }

    projects_endpoint = proj_resource["/_api/ProjectServer/Projects"]

    puts "Creating the project" if @enable_debug_logging
    begin
      results = projects_endpoint.post create_params.to_json
    rescue RestClient::Exception => error
      raise StandardError, handle_error(error)[:message]
    end

    json = JSON.parse(results)
    puts json.inspect if @enable_debug_logging
    project_id = json['Id']
    puts "Project has an id of '#{project_id}'" if @enable_debug_logging
    puts "Returning the results" if @enable_debug_logging

    <<-RESULTS
    <results>
      <result name="project_id">#{project_id}</result>
    </results>
    RESULTS
  end

  def handle_error(error)
    error_message = error.inspect
    code = nil
    value = nil
    needs_retry = false
    begin
      json = JSON.parse(error.response.to_s)
      if !json["odata.error"].nil?
        if !json["odata.error"]["message"].nil? && !json["odata.error"]["message"]["value"].nil?
          error_message = json["odata.error"]["message"]["value"].to_s
          value = json["odata.error"]["message"]["value"]
        end

        # If a project is equal to the following codes, it the retry variable 
        # will be set to true because they are non-fatal 403's
        if json["odata.error"]["code"] == "1030, Microsoft.ProjectServer.PJClientCallableException" || # ProjectWriteLock
          json["odata.error"]["code"] == "10103, Microsoft.ProjectServer.PJClientCallableException" # Checked out in other session
          needs_retry = true
        end

        if !json["odata.error"]["code"].nil?
          if json["odata.error"]["code"].split(",").length > 1
            if json["odata.error"]["code"].split(",")[1].strip == "Microsoft.SharePoint.Client.ResourceNotFoundException"
              error_message = "Invalid Project: Can't find a project with an id of '#{@parameters['project_id']}'"
            else
              code = json["odata.error"]["code"].split(",")[0].strip
            end
          end
        end
      end
    rescue Exception
      # If the Response data can't be parsed, throw a standard error
      raise StandardError, error.inspect
    end

    if code != nil && value != nil
      error_message = "Error Name: #{value}, Code: #{code}. Too see more details about this error, see Project Server 2013 error codes (https://msdn.microsoft.com/en-us/library/office/ms508961.aspx)."
    end

    {:retry => needs_retry, :message => error_message}
  end

  # This is a template method that is used to escape results values (returned in
  # execute) that would cause the XML to be invalid.  This method is not
  # necessary if values do not contain character that have special meaning in
  # XML (&, ", <, and >), however it is a good practice to use it for all return
  # variable results in case the value could include one of those characters in
  # the future.  This method can be copied and reused between handlers.
  def escape(string)
    # Globally replace characters based on the ESCAPE_CHARACTERS constant
    string.to_s.gsub(/[&"><]/) { |special| ESCAPE_CHARACTERS[special] } if string
  end
  # This is a ruby constant that is used by the escape method
  ESCAPE_CHARACTERS = {'&'=>'&amp;', '>'=>'&gt;', '<'=>'&lt;', '"' => '&quot;'}
end