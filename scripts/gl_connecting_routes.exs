defmodule GLConnectingRoutes do
  @moduledoc """
  Prints a JSON object or TSV table that maps all Green Line parent station IDs to the routes
  that serve their connecting stops.
  """

  alias ApiQueries.V3Api

  def get_connecting_routes do
    name_by_parent_station = get_name_by_parent_station()

    connecting_stops_by_parent_station =
      name_by_parent_station
      |> Map.keys()
      |> get_connecting_stop_ids()

    routes_by_connecting_stop =
      connecting_stops_by_parent_station
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
      |> Task.async_stream(&get_routes_by_stop/1, ordered: false)
      |> Enum.into(%{}, fn {:ok, entry} -> entry end)

    for {parent_station, connecting_stops} <- connecting_stops_by_parent_station, into: %{} do
      {parent_station,
       %{
         name: name_by_parent_station[parent_station],
         connecting_routes:
           connecting_stops_to_connecting_routes(connecting_stops, routes_by_connecting_stop)
       }}
    end
  end

  def as_json(connecting_routes) do
    Jason.encode!(connecting_routes, pretty: true)
  end

  def as_tsv(connecting_routes) do
    connecting_routes
    |> Enum.map(fn {parent_station_id, info} ->
      connecting_route_names =
        info.connecting_routes
        |> Enum.map(fn
          %{name: name} -> name
          name -> name
        end)
        |> Enum.intersperse(?,)

      [parent_station_id, ?\t, info.name, ?\t, connecting_route_names]
    end)
    |> Enum.intersperse(?\n)
    |> then(fn body -> ["id\tname\tconnecting route names\n", body] end)
    |> IO.iodata_to_binary()
  end

  defp get_name_by_parent_station do
    "stops"
    |> V3Api.fetch_resource!(%{
      "filter[route_type]" => "0",
      "include" => "parent_station",
      "fields[stop]" => "name"
    })
    |> Map.fetch!("included")
    |> Enum.into(%{}, fn parent_station ->
      {parent_station["id"], parent_station["attributes"]["name"]}
    end)
  end

  defp get_connecting_stop_ids(parent_station_ids) do
    "stops"
    |> V3Api.fetch_resource!(%{
      "filter[id]" => parent_station_ids,
      "include" => "connecting_stops"
    })
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
    |> V3Api.fetch_resource!(%{"filter[stop]" => stop_id, "fields[route]" => "short_name"})
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

case System.argv() do
  ["--json"] ->
    GLConnectingRoutes.get_connecting_routes()
    |> GLConnectingRoutes.as_json()
    |> IO.puts()

  ["--tsv"] ->
    GLConnectingRoutes.get_connecting_routes()
    |> GLConnectingRoutes.as_tsv()
    |> IO.puts()

  _ ->
    IO.puts("Specify output format: either --json or --tsv")
end
