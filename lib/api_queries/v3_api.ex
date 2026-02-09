defmodule ApiQueries.V3Api do
  @moduledoc false

  @api_key_name "API_V3_KEY"

  def fetch_resource!(resource, query) do
    {:ok, resource} = fetch_resource(resource, query)
    resource
  end

  def fetch_resource(resource, query) do
    with {:ok, %{status_code: 200, body: body}} <-
           HTTPoison.get(resource_url(resource), api_key_headers(), params: prepare_query(query)),
         {:ok, parsed} <- JSON.decode(body) do
      {:ok, parsed}
    else
      error ->
        IO.inspect(error, label: "fetch error")
        :error
    end
  end

  defp resource_url(resource) do
    "https://api-v3.mbta.com/"
    |> URI.parse()
    |> URI.merge(resource)
    |> to_string()
  end

  defp prepare_query(query) do
    Enum.map(query, fn
      {k, v} when is_list(v) -> {k, Enum.join(v, ",")}
      entry -> entry
    end)
  end

  defp api_key_headers do
    case System.get_env(@api_key_name) do
      nil -> []
      key -> [{"x-api-key", key}]
    end
  end
end
