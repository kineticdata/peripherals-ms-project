#MSProject Project Task Assign

  This handler assigns an Enterprise Resource to a Task.

#Parameters

[Project Id]  - The id of the project that contains the task that will be assigned.

[Task Id]   - The id of the task that will be assigned.

[Resource Id]   - The id of the Enterprise Resource that will be assigned to the task.

#Results

This handler returns no results

#Sample Configuration

Project Id:                   db521c56-44ab-422d-9abd-29d8d359043a

Task Id:                      5e4aa3ed-f55e-4c63-818f-b84bab4822a1

Resource Id:                  d7d23bc0-8424-47d5-b837-ea97e96e1ca2

#Detailed Description

This handler makes a REST call Microsoft Project Online to the Project Server
API to assign an Enterprise Resource to an already existing Task. After
authenticating against the Project Server using the inputted username and
password, the handler first makes a call to Project to get a FormDigestValue
which is needed as a part of the authentication for future calls. The inputted
Resource Id is then checked against the Resource list of the project and will be
added to the Project if the inputted Id is not present. After the Resource has
been verified to be attached to the Project, an Assignment is created using the
Task Id and Resource Id. Any errors that occur during this process will be
caught and re-raised by the handler.
