crypto = require 'crypto'

class User

  authenticate: (database) =>
    username = Cookie.get("applicationUsername")
    password = Cookie.get("applicationPassword")

    unless username and password
      router.navigate "server/#{Tamarind.serverName}", trigger:true

    userData = await database.get("user.#{username}")
    salt = ""
    hashKeyForPassword = (crypto.pbkdf2Sync password, salt, 1000, 256/8, 'sha256').toString('base64')
    if userData.password is hashKeyForPassword
      _(@).extend userData
      true
    else
      false

  has: (property) =>
    return true
    return @[property]? and not ["no", "false", false].includes @[property]

module.exports = User
