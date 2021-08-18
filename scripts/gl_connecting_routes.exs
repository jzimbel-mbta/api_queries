defmodule GLConnectingRoutes do
  @moduledoc """
  Prints a JSON object that maps all Green Line parent station IDs to the routes that serve
  their connecting stops.
  """

  alias ApiQueries.V3Api

  def get_connecting_routes do
    gl_parent_stations = get_gl_parent_station_ids()
    connecting_stops_by_parent_station = get_connecting_stop_ids(gl_parent_stations)

    routes_by_connecting_stop =
      connecting_stops_by_parent_station
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> Task.async_stream(&get_routes_by_stop/1, ordered: false)
      |> Enum.into(%{}, fn {:ok, entry} -> entry end)

    for {parent_station, connecting_stops} <- connecting_stops_by_parent_station, into: %{} do
      {parent_station,
       connecting_stops_to_connecting_routes(connecting_stops, routes_by_connecting_stop)}
    end
  end

  defp get_gl_parent_station_ids do
    "stops"
    |> V3Api.fetch_resource!(%{"filter[route_type]" => "0", "include" => "parent_station"})
    |> get_in(["data", Access.all(), "relationships", "parent_station", "data", "id"])
    |> Enum.uniq()
  end

  defp get_connecting_stop_ids(station_ids) do
    "stops"
    |> V3Api.fetch_resource!(%{"filter[id]" => station_ids, "include" => "connecting_stops"})
    |> Map.fetch!("data")
    |> Enum.into(%{}, fn stop_entity ->
      {
        stop_entity["id"],
        get_in(stop_entity, ["relationships", "connecting_stops", "data", Access.all(), "id"])
      }
    end)
  end

  defp get_routes_by_stop(stop_id) when is_binary(stop_id) do
    "routes"
    |> V3Api.fetch_resource!(%{"filter[stop]" => stop_id})
    |> Map.fetch!("data")
    |> Enum.map(fn route_entity ->
        id = route_entity["id"]
        name = route_entity["attributes"]["short_name"]

        case {id, name} do
          {id, id} -> id
          {id, name} -> %{id: id, name: name}
        end
    end)
    |> then(fn routes -> {stop_id, routes} end)
  end

  defp connecting_stops_to_connecting_routes(connecting_stops, routes_by_connecting_stop) do
    connecting_stops
    |> Enum.flat_map(&Map.fetch!(routes_by_connecting_stop, &1))
    |> Enum.uniq()
  end
end

GLConnectingRoutes.get_connecting_routes()
|> Jason.encode!(pretty: true)
|> IO.puts()
