expect = require 'expect.js'
api = require '../src/invitations-api'

Invitation = api.Invitation

describe 'Invitation', () ->
  describe '.getId()', () ->
    type = 'game-type'
    from = 'alice'
    to = 'bob'
    genId = Invitation.getId.bind(Invitation, type)

    it 'generates 16 byte long hex strings for ids', () ->
      id = genId(from, to)
      expect(id).to.match(/[a-z0-9]{32}/)

    it 'generates same IDs for (X invites Y) and (Y invites X) given same type',
    () ->
      id = genId(from, to)
      idReversed = genId(to, from)
      idOtherType = Invitation.getId("other-#{type}", from, to)

      expect(id).to.be(idReversed)
      expect(id).not.to.be(idOtherType)

    # https://github.com/j3k0/ganomede-invitations/commit/ad5be3d552b3968d10cccb7d8969fe04bd612bcd#commitcomment-10482685
    it 'prevents funny buisness with usernames highjacking', () ->
      id1 = genId('a-b', 'c')
      id2 = genId('a', 'b-c')
      expect(id1).not.to.be(id2)
