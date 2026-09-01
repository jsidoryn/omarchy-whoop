# frozen_string_literal: true

require_relative "omarchy_whoop/errors"
require_relative "omarchy_whoop/subprocess"
require_relative "omarchy_whoop/callback_handler"
require_relative "omarchy_whoop/secret_store"
require_relative "omarchy_whoop/http"
require_relative "omarchy_whoop/oauth"
require_relative "omarchy_whoop/api"
require_relative "omarchy_whoop/presenter"
require_relative "omarchy_whoop/demo"
require_relative "omarchy_whoop/client"
require_relative "omarchy_whoop/cli"

module OmarchyWhoop
  VERSION = "0.2.0"
end
