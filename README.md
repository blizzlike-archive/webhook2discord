# webhook2discord

this is a wrapper for the [discord webhook api](https://discordapp.com/).
At the moment discord only supports a few services like github for their webhooks.
This peace of software wraps the [travis](https://travis-ci.org) webhook body to a generic
`embed object` and forwards it to the configured webhook address.

## install

    docker pull blizzlike/webhook2discord:stable
    docker run \
      --name w2d -d \
      -p 8085:80/tcp \
      -e DISCORD_WEBHOOK_URL="<your-discord-webhook-link>" blizzlike/webhook2discord:stable ./run.sh

the travis webhook provides a public key to verify the request body with the `Signature` header.

## usage

    # .travis.yml
    notifications:
      webhooks:
        urls:
          - http://<fqdn>:8085/v1/travis
