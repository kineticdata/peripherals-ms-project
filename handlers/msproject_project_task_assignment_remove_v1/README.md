#MSProject Project Task Assignment Remove

  This handler removes an assignment from an existing task in Microsoft Project.

#Parameters

[Project Id] - The id of the project that contains the task that the assignment will be removed from.

[Task Id] - The id of the task that the assignment should be removed from.

[Resource Email] - The email that will be unassigned from the task. If left blank, all Assignments will be removed from the task.

#Results

This handler returns no results

#Sample Configuration

Project Id:                   db521c56-44ab-422d-9abd-29d8d359043a

Task Id:                      5e4aa3ed-f55e-4c63-818f-b84bab4822a1

Resource Email:               Demo.User@acme.com

#Detailed Description

This handler makes a REST call to Microsoft Project Online to the Project Server
API to remove an assignment from an existing task within a project. After
authenticating against Project Server using the inputted username and password,
the handler first makes a call to Project to get a FormDigestValue which is
needed as a part of the authentication for future calls. All assignments for a
task are returned using the specified project id and task id. If a Resource Email
has been specified, the handler will only delete assignments that have that
specified email address match the assignment resource email. If no email is
passed, all assignments attached to the task will be deleted. Any errors that
occur during this process will be caught and re-raised by the handler.