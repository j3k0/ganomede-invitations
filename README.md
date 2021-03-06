Invitations
-----------

This module allows player to invite each other to play a game.

Relations
---------

 * "InvitationsDB" (Redis) -> to store the list of invitations for each user
 * "AuthDB" (Redis) -> to check authentication status of user making requests
   * see https://github.com/j3k0/node-authdb
   * request sample code to JC

Configuration
-------------

Variables available for service configuration.

 * `REDIS_INVITATIONS_PORT_6379_TCP_ADDR` - IP of the InvitationsDB redis
 * `REDIS_INVITATIONS_PORT_6379_TCP_PORT` - Port of the InvitationsDB redis
 * `REDIS_AUTH_PORT_6379_TCP_ADDR` - IP of the AuthDB redis
 * `REDIS_AUTH_PORT_6379_TCP_PORT` - Port of the AuthDB redis
 * `REDIS_USERMETA_PORT_6379_TCP_ADDR` - IP of the UsermetaDB redis
 * `REDIS_USERMETA_PORT_6379_TCP_PORT` - Port of the UsermetaDB redis
 
 * `API_SECRET` - For sending notifications
 * `NOTIFICATIONS_PORT_8080_TCP_ADDR` - IP of the Notifications service
 * `NOTIFICATIONS_PORT_8080_TCP_PORT` - Port of the Notifications service

InvitationDB
------------

 * Contains a store:
   * "invitation-id" -> Invitation serialized to JSON
   * "username" -> Set of Invitation IDs where username is either receiver (to) or sender (from) of inivitation

See #4 for details.

AuthDB
------

 * Contains a store "authToken" -> { "username": "someusername", ... }
 * Access it using node-authdb

UsermetaDB
----------

 * Contains a store "userA:$blocked" -> "user1,user2,user3"

It contains the list of users that "userA" has blocked. Invitations from users in this list won't be sent to "userA".

Note, this database contains metadata for all users.

Background Jobs
---------------

 * Delete invitations older that 15 days.
   * Can surely be done using redis' expire feature. See: https://github.com/j3k0/node-authdb/blob/master/authdb.js#L48

API
---

# Invitations [/invitations/v1/auth/:authToken/invitations]

    + Parameters
        + authToken (string, required) ... Authentication token

## Create an invitation [POST]

### body (application/json)

    {
        "gameId": "0123456789abcdef012345",
        "type": "triominos/v1"
        "to": "some_username",
    }

### response [200] OK

    {
        "id": "0123456789abcdef012345"
    }

### response [401] Unauthorized

If authToken is invalid.

### response [423] Blocked

If the user is not allowed to send this invitation (for example she/he has been blocked).

Note: Error code would better be `403`, but the game using this module will show a login screen when `403` is returned. That's why we chose code `423`.


## List user's invitations [GET]

### response [200] OK

    [
        {
            "id": "0123456789abcdef012345",
            "from": "some_username",
            "to": "my_username",
            "gameId": "0123456789abcdef012345",
            "type": "triominos/v1"
        },
        {
            "id": "0123456789abcdef012345",
            "from": "my_username",
            "to": "some_username",
            "gameId": "0123456789abcdef012345",
            "type": "triominos/v1"
        },
        {
            "id": "0123456789abcdef012345",
            "from": "my_username",
            "to": "some_username",
            "gameId": "0123456789abcdef012345",
            "type": "wordsearch/v1"
        }
    ]

### response [401] Unauthorized

# Single Invitation [/invitations/v1/auth/:authToken/invitations/:id]

    + Parameters

        + authToken (string, required) ... Authentication token
        + id (string, required) ... ID of the invitation

## Delete an invitation [DELETE]

An invitation can only be deleted by one of the two players concerned bt the invitation.

"from" player can DELETE it only with reason: "cancel"

"to" player can DELETE it only with reasons: "accept" or "refuse"

After deletion is successful, the invitation is removed from database (for the two players).

### body (application/json)

    {
        "reason": "accept"
    }

### response [204] No content

    {
        "ok": true
    }

### response [401] Unauthorized

### Alternative endpoint

Deleting an invitation can also be done using `POST` at the following endpoint:

    /invitations/v1/auth/:authToken/invitations/:id/delete

This endpoint has the exact same behaviour as the above documented DELETE.. It's useful for platforms that do not support the DELETE method.
