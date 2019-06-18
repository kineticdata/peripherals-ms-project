# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))
# Require the Office 365 Authentication file
require File.expand_path(File.join(File.dirname(__FILE__), 'o365_authentication'))

class MsprojectProjectCustomFieldUpdateV1
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

    custom_fields_endpoint = proj_resource["/_api/ProjectServer/CustomFields"]
    puts "Retrieving the Custom Field Id"
    begin
      results = custom_fields_endpoint.get
    rescue RestClient::Exception => error
      raise StandardError, handle_error(error)[:message]
    end

    json = JSON.parse(results)

    # Alternate names to account for fields that are the same but named
    # differently across servers
    alt_names = {"Requested End" => "Requested Finish", "Project Manager" => "Project Mgr"}
    alt_names.merge!(alt_names.invert)

    custom_field_guid = find_guid(@parameters["custom_field_name"], json)
    custom_field_guid = find_guid(alt_names[@parameters["custom_field_name"]],json) if custom_field_guid.nil?

    if custom_field_guid == nil
      throw new StandardError, "The Custom Field '#{@parameters['custom_field_name']}' could not be found.'"
    end

    # Make sure that the project is already checked in when the handler attempts
    # to update. If it is not checked in already, try again every 10 seconds
    # for a minute before throwing an error.
    for attempt in 0..30
      checked_out = is_project_checked_out(@parameters['project_id'],attempt,proj_resource)
      if checked_out == false
        break
      end
    end

    puts "Attempting to add the value to the custom field '#{@parameters['custom_field_name']}'" if @enable_debug_logging
    params = {
      "projectId" => @parameters['project_id'],
      "propertyId" => custom_field_guid,
      "value" => @parameters['custom_field_value']
    }
    if /^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/.match(@parameters['custom_field_value'])
      puts "Updating Guid Property" if @enable_debug_logging
      workflow_endpoint = proj_resource["/_api/ProjectServer/WorkflowActivities/updateGuidProperty"]
    elsif /^\d{4}-\d{2}-\d{2}(?:T\d+:\d+:\d+)?Z?$/.match(@parameters['custom_field_value'])
      # Allows matching either 2014-12-14 or 2014-1-1T00:00:00
      puts "Updating DateTime Property" if @enable_debug_logging
      workflow_endpoint = proj_resource["/_api/ProjectServer/WorkflowActivities/updateDateTimeProperty"]
    else
      puts "Updating Text Property" if @enable_debug_logging
      workflow_endpoint = proj_resource["/_api/ProjectServer/WorkflowActivities/updateTextProperty"]
    end
    workflow_endpoint.headers["X-RequestDigest"] = form_digest_value

    begin
      workflow_endpoint.post params.to_json
    rescue RestClient::Exception => error
      raise StandardError, handle_error(error)[:message]
    end

    puts "Value successfully added to the custom field '#{@parameters['custom_field_name']}'"

    # Return the results
    <<-RESULTS
    <results/>
    RESULTS
  end

  def is_project_checked_out(project_id, attempt_number, proj_resource)
    checked_out = true

    puts "Checking if the project is currently checked out" if @enable_debug_logging
    begin
      project = proj_resource["/_api/ProjectServer/Projects('#{project_id}')"].get
    rescue RestClient::Exception => error
      puts error.inspect if @enable_debug_logging
      raise StandardError, "Error occurred trying to retrieve the project with an id of '#{project_id}'"
    end

    json = JSON.parse(project)
    if json["IsCheckedOut"] == false
      puts "Project is not checked out, fields can now be updated." if @enable_debug_logging
      checked_out = false
    end

    if attempt_number >= 30
      raise StandardError, "Project cannot be checked back in. Please manually check it in and try again."
    elsif checked_out == true
      puts "Project is still checked out. Will try again #{30-attempt_number} more time(s)." if @enable_debug_logging
      sleep(10)
    end

    return checked_out
  end

  def find_guid(field, json)
    guid = nil
    for field_obj in json["value"]
      if field_obj["Name"] == field
          guid = field_obj["Id"]
          break
      end
    end
    return guid
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