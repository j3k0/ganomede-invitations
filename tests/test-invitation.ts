/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const expect = require('expect.js');
const api = require('../src/invitations-api');

const {
  Invitation
} = api;

describe('Invitation', () => describe('.getId()', function() {
  const type = 'game-type';
  const from = 'alice';
  const to = 'bob';
  const genId = Invitation.getId.bind(Invitation, type);

  it('generates 16 byte long hex strings for ids', function() {
    const id = genId(from, to);
    return expect(id).to.match(/[a-z0-9]{32}/);
  });

  it('generates same IDs for (X invites Y) and (Y invites X) given same type',
  function() {
    const id = genId(from, to);
    const idReversed = genId(to, from);
    const idOtherType = Invitation.getId(`other-${type}`, from, to);

    expect(id).to.be(idReversed);
    return expect(id).not.to.be(idOtherType);
  });

  // https://github.com/j3k0/ganomede-invitations/commit/ad5be3d552b3968d10cccb7d8969fe04bd612bcd#commitcomment-10482685
  return it('prevents funny buisness with usernames highjacking', function() {
    const id1 = genId('a-b', 'c');
    const id2 = genId('a', 'b-c');
    return expect(id1).not.to.be(id2);
  });
}));
