# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))
# Require the Office 365 Authentication file
require File.expand_path(File.join(File.dirname(__FILE__), 'o365_authentication'))

class MsprojectProjectTaskAssignmentRemoveV1
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

    proj_resource = RestClient::Resource.new(@info_values['ms_project_location'],
    :headers => {:content_type => "application/json",:accept => "application/json", :cookie => cookies})

    set_form_digest(proj_resource)

    project_id = @parameters['project_id']
    task_id = @parameters['task_id']

    # Check if Resource has already been added to the project. If it hasn't,
    # add it.
    task_assignments_endpoint = proj_resource["/_api/ProjectServer/Projects('#{project_id}')/Draft/Tasks('#{task_id}')/Assignments"]

    begin
      resp = task_assignments_endpoint.get
    rescue RestClient::Exception => error
      raise
    end

    # Retrieve all assignment ids related to the project
    assign_json = JSON.parse(resp)
    assignment_ids = []
    for assignment in assign_json["value"]
      assignment_ids.push(assignment["Id"])
    end

    for id in assignment_ids
      assignment_endpoint = proj_resource["/_api/ProjectServer/Projects('#{project_id}')/Draft/Assignments('#{id}')"]
      delete_assignment = true
      if !@parameters['resource_email'].to_s.empty?
        assignment_resource_endpoint = assignment_endpoint["/Resource"]
        resp = assignment_resource_endpoint.get
        json = JSON.parse(resp)
        delete_assignment = false if json["Email"].downcase != @parameters['resource_email'].downcase
      end

      begin
        assignment_endpoint.delete
      rescue RestClient::Exception => error
        handle_error(error)
      end
    end

    puts "Returning results" if @enable_debug_logging
    return "<results/>"
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

  def set_form_digest(proj_resource)
    context_endpoint = proj_resource["/_api/contextinfo"]
    puts "Sending a request to get the FormDigestValue that will be passed at the X-RequestDigest header in the create call" if @enable_debug_logging == true
    begin
      results = context_endpoint.post ""
    rescue RestClient::Exception => error
      raise StandardError, error.inspect
    end

    json = JSON.parse(results)
    # Get the JSON value array that contains the lookup table information
    form_digest_value = json["FormDigestValue"]
    puts "Retrieved Form Digest: #{form_digest_value}" if @enable_debug_logging
    proj_resource.headers["X-RequestDigest"] = form_digest_value
  end

  def is_resource_in_project?(proj_resource, proj_id, res_id)
    resource_in_project = false

    retrieve_resources_endpoint = proj_resource["/_api/ProjectServer/Projects('#{proj_id}')/ProjectResources"]
    puts "Retrieving the resource from the Project" if @enable_debug_logging
    begin
      results = retrieve_resources_endpoint.get
    rescue RestClient::Exception => error
      raise StandardError, error.inspect
    end

    json = JSON.parse(results)
    project_resources = []
    for resource in json["value"]
      project_resources.push({:name => resource["Name"], :email => resource["Email"], :id => resource["Id"]})
    end

    puts project_resources
    for res in project_resources
      if res[:id] == res_id
        resource_in_project = true
      end
    end

    return resource_in_project
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