_          = require("lodash")
os         = require("os")
nmi        = require("node-machine-id")
request    = require("request-promise")
errors     = require("request-promise/errors")
Promise    = require("bluebird")
pkg        = require("@packages/root")
browsers   = require('./browsers')
routes     = require("./util/routes")
system     = require("./util/system")
debug      = require("debug")("cypress:server:api")

## TODO: improve this, dont just use
## requests because its way too verbose
# if debug.enabled
#   request.debug = true

rp = request.defaults (params = {}, callback) ->
  _.defaults(params, {
    gzip: true
  })

  headers = params.headers ?= {}

  _.defaults(headers, {
    "x-os-name":         os.platform()
    "x-cypress-version": pkg.version
  })

  method = params.method.toLowerCase()

  debug(
    "request to url: %s with params: %o",
    "#{params.method} #{params.url}",
    _.pick(params, "body", "headers")
  )

  request[method](params, callback)
  .promise()
  .tap (resp) ->
    debug("response %o", resp)

formatResponseBody = (err) ->
  ## if the body is JSON object
  if _.isObject(err.error)
    ## transform the error message to include the
    ## stringified body (represented as the 'error' property)
    body = JSON.stringify(err.error, null, 2)
    err.message = [err.statusCode, body].join("\n\n")

  throw err

tagError = (err) ->
  err.isApiError = true
  throw err

machineId = ->
  nmi.machineId()
  .catch ->
    return null

module.exports = {
  rp

  ping: ->
    rp.get(routes.ping())
    .catch(tagError)

  getOrgs: (authToken) ->
    rp.get({
      url: routes.orgs()
      json: true
      auth: {
        bearer: authToken
      }
    })
    .catch(tagError)

  getProjects: (authToken) ->
    rp.get({
      url: routes.projects()
      json: true
      auth: {
        bearer: authToken
      }
    })
    .catch(tagError)

  getProject: (projectId, authToken) ->
    rp.get({
      url: routes.project(projectId)
      json: true
      auth: {
        bearer: authToken
      }
      headers: {
        "x-route-version": "2"
      }
    })
    .catch(tagError)

  getProjectRuns: (projectId, authToken, options = {}) ->
    options.page ?= 1

    rp.get({
      url: routes.projectRuns(projectId)
      json: true
      timeout: options.timeout ? 10000
      auth: {
        bearer: authToken
      }
      headers: {
        "x-route-version": "2"
      }
    })
    .catch(errors.StatusCodeError, formatResponseBody)
    .catch(tagError)

  createRun: (options = {}) ->
    body = _.pick(options, [
      "ci"
      "specs",
      "commit"
      "group",
      "platform",
      "parallel",
      "ciBuildId",
      "projectId",
      "recordKey",
      "specPattern",
    ])

    rp.post({
      body
      url: routes.runs()
      json: true
      timeout: options.timeout ? 10000
      headers: {
        "x-route-version": "4"
      }
    })
    .catch(errors.StatusCodeError, formatResponseBody)
    .catch(tagError)

  createInstance: (options = {}) ->
    { runId, timeout } = options

    body = _.pick(options, [
      "spec"
      "groupId"
      "machineId"
      "platform"
    ])

    rp.post({
      body
      url: routes.instances(runId)
      json: true
      timeout: timeout ? 10000
      headers: {
        "x-route-version": "5"
      }
    })
    .catch(errors.StatusCodeError, formatResponseBody)
    .catch(tagError)

  updateInstanceStdout: (options = {}) ->
    rp.put({
      url: routes.instanceStdout(options.instanceId)
      json: true
      timeout: options.timeout ? 10000
      body: {
        stdout: options.stdout
      }
    })
    .catch(errors.StatusCodeError, formatResponseBody)
    .catch(tagError)

  updateInstance: (options = {}) ->
    rp.put({
      url: routes.instance(options.instanceId)
      json: true
      timeout: options.timeout ? 10000
      headers: {
        "x-route-version": "2"
      }
      body: _.pick(options, [
        "stats"
        "tests"
        "error"
        "video"
        "hooks"
        "stdout"
        "screenshots"
        "cypressConfig"
        "reporterStats"
      ])
    })
    .catch(errors.StatusCodeError, formatResponseBody)
    .catch(tagError)

  createRaygunException: (body, authToken, timeout = 3000) ->
    rp.post({
      url: routes.exceptions()
      json: true
      body: body
      auth: {
        bearer: authToken
      }
    })
    .timeout(timeout)
    .catch(tagError)

  createSignin: (code) ->
    machineId()
    .then (id) ->
      h = {
        "x-route-version": "3"
        "x-accept-terms": "true"
      }

      if id
        h["x-machine-id"] = id

      rp.post({
        url: routes.signin({code: code})
        json: true
        headers: h
      })
      .catch errors.StatusCodeError, (err) ->
        ## reset message to error which is a pure body
        ## representation of what was sent back from
        ## the API
        err.message = err.error

        throw err
      .catch(tagError)

  createSignout: (authToken) ->
    rp.post({
      url: routes.signout()
      json: true
      auth: {
        bearer: authToken
      }
    })
    .catch({statusCode: 401}, ->) ## do nothing on 401
    .catch(tagError)

  createProject: (projectDetails, remoteOrigin, authToken) ->
    rp.post({
      url: routes.projects()
      json: true
      auth: {
        bearer: authToken
      }
      headers: {
        "x-route-version": "2"
      }
      body: {
        name: projectDetails.projectName
        orgId: projectDetails.orgId
        public: projectDetails.public
        remoteOrigin: remoteOrigin
      }
    })
    .catch(errors.StatusCodeError, formatResponseBody)
    .catch(tagError)

  getProjectRecordKeys: (projectId, authToken) ->
    rp.get({
      url: routes.projectRecordKeys(projectId)
      json: true
      auth: {
        bearer: authToken
      }
    })
    .catch(tagError)

  requestAccess: (projectId, authToken) ->
    rp.post({
      url: routes.membershipRequests(projectId)
      json: true
      auth: {
        bearer: authToken
      }
    })
    .catch(errors.StatusCodeError, formatResponseBody)
    .catch(tagError)

  getLoginUrl: ->
    rp.get({
      url: routes.auth(),
      json: true
    })
    .get("url")
    .catch(tagError)

  _projectToken: (method, projectId, authToken) ->
    rp({
      method: method
      url: routes.projectToken(projectId)
      json: true
      auth: {
        bearer: authToken
      }
      headers: {
        "x-route-version": "2"
      }
    })
    .get("apiToken")
    .catch(tagError)

  getProjectToken: (projectId, authToken) ->
    @_projectToken("get", projectId, authToken)

  updateProjectToken: (projectId, authToken) ->
    @_projectToken("put", projectId, authToken)

}
