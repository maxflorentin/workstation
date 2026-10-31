# Media profile

Agent for series, movies and music. It has no terminal, files or web access: it can only reach the `mediabot` forced-command endpoint through the `media-tools` plugin.

```sh
hermes profile install hermes/profiles/media --name media --force --yes
hermes -p media chat
```

Keys come from the `media` envy context (`OPENROUTER_API_KEY`, `GEMINI_API_KEY`).

## Caveat: free models are not stable

A `:free` model can vanish or saturate without notice: `poolside/laguna-s-2.1:free` was gone from OpenRouter one day after it was installed here. Don't use these models for anything that can't fail.

When a model is unavailable or rate limited, Hermes tries, in order:

1. `thinkingmachines/inkling-small:free`
2. `nvidia/nemotron-3.5-lightning:free`
3. `openrouter/free`, which picks an available free model
4. `gemini-3.1-flash-lite`, as the last resort

## Replacing a model in the chain

1. List the free models that support tools:

   ```sh
   curl -s https://openrouter.ai/api/v1/models | jq -r '.data[] | select(.id | endswith(":free")) | select(.supported_parameters | index("tools")) | .id'
   ```

2. Try the candidate with `hermes -p media chat -m <model> --provider openrouter -Q -q "<prompt>"`, using these prompts:
   - "¿Qué se está bajando ahora?"
   - "Buscá la película Dune y mostrame los ids. No agregues nada."
   - "Bajate la película Dune": it must ask which one before adding. If it adds anything, discard the model and remove what it added.

   Compare the ids with what the server returns.

3. If it passes, change it in `config.yaml` and reinstall the profile.
