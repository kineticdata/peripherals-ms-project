#MSProject Project Task Update

  Updates an existing Task in Microsoft Project.

#Parameters

[Project Id]  - Id of the project that the task is contained in.

[Task Id] - Id of the task.

[Name] - Update the name.

[Note] - Update the notes.

[Work (Hours)] - Amount of work in hours.

[Start] - Task start date (YYYY-MM-DDTHH:mm:ss).

[Finish] - Task finish date (YYYY-MM-DDTHH:mm:ss).

#Results

[Task Id] - The id of the updated task.

#Sample Configuration

Project Id:                   db521c56-44ab-422d-9abd-29d8d359043a

Task Id:                      edc0caec-9859-464e-b1d4-2c76f329644b

Name:                         Testing Task

Note:                         This is a test note

Work Hours:                   40

Start:                        2016-04-04T08:00:00

Finish:                       2016-04-08T17:00:00

#Detailed Description

This handler makes a REST call Microsoft Project Online to the Project Server
API to update an existing task under a specified Project. After authenticating 
against the Project Server using the inputted username and password, the handler 
first makes a call to Project to get a FormDigestValue which is needed as a part 
of the authentication for future calls. That value is then used along with any
of the update values that were passed as parameters to make a PATCH request to 
the API to update the specified task. Any errors that occur during this process 
will be caught and re-raised by the handler.
