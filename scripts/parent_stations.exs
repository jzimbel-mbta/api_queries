defmodule ParentStations do
  @moduledoc """
  Prints an elixir map mapping child/platform stop IDs to parent station IDs.

  Usage:
      mix run scripts/parent_stations.exs stop_id1 stop_id2 ... stop_idN
  """

  alias ApiQueries.V3Api

  def get_parent_station_id_mapping(stop_ids) do
    mapping =
      "stops"
      |> V3Api.fetch_resource!(%{
        "filter[id]" => Enum.join(stop_ids, ","),
        "fields[stop]" => ""
      })
      |> Map.fetch!("data")
      |> Map.new(fn stop_data ->
        {stop_data["id"], stop_data["relationships"]["parent_station"]["data"]["id"]}
      end)

    missing = stop_ids -- Map.keys(mapping)

    if missing == [] do
      IO.inspect(mapping)
    else
      IO.inspect(missing, label: "** Invalid stop IDs:")
    end
  end
end

System.argv()
|> Enum.uniq()
|> ParentStations.get_parent_station_id_mapping()
