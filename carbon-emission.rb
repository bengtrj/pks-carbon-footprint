#!/usr/bin/ruby
# frozen_string_literal: true

require 'json'
require 'yaml'

# dependencies:
# Maybe use OM to figure these out?
# BOSH environment credentials
# PKS environment credentials  $PKS_UAA_API $PKS_UAA_USER $PKS_UAA_PASSWORD ca-cert

class Cluster

  attr_reader :name, :cpus, :disks, :ram

  def initialize(name:, cpus:, disks:, ram:)
    @name = name
    @cpus = cpus
    @disks = disks
    @ram = ram
  end

end

def compute_vms_from_pks_foundation
  pks_clusters = `pks clusters --json | jq -r -c 'map({ cluster_name: .name, deployment_name: "service-instance_\\(.uuid)" })'`
  vm_types = YAML.load(`bosh cloud-config`)['vm_types']

  clusters = JSON.parse(pks_clusters)

  clusters.each do |cluster|
    cluster_name = cluster['cluster_name']
    cluster_vm_types = `bosh vms -d "#{cluster['deployment_name']}" --json | jq -r '.Tables | .[] | .Rows | .[] | .vm_type'`.split("\n").to_enum
    vm_types_count = Hash[cluster_vm_types.group_by(&:itself).map { |k, v| [k, v.size] }]

    cpus = 0
    disks = 0
    ram = 0

    vm_types_count.each do |name, count|
      whatever = vm_types.select { |vm_type| vm_type['name'] == name }
      vm_type = whatever[0]['cloud_properties']

      cpus += vm_type['cpu'].to_i * count
      disks += count
      ram += vm_type['ram'].to_i * count
    end

    print_trees(
      Cluster.new(name: cluster_name,
                  cpus: cpus,
                  disks: disks,
                  ram: ram)
    )
  end

end

KWH_VCPU_DAY = 120.0 / 1000
KWH_DISK_DAY = (9.0 * 24) / 1000
KWH_RAM_DAY = (0.0003638 * 24) / 1000 # 1.49W for 4gb - 0.3725 per GB - 0.0003638 per MB
KWH_TREE = 0.012
KWH_CO2 = 0.707

# @param [Object] cluster
def print_trees(cluster)
  vcpu = cluster.cpus
  ram = cluster.ram
  disks = cluster.disks

  days = ARGV[0].to_i == 0 ? 30 : ARGV[0].to_i

  cpu_kwh_day = vcpu * KWH_VCPU_DAY * days
  ram_kwh_day = ram * KWH_RAM_DAY * days
  disks_kwh_day = disks * KWH_DISK_DAY * days
  total_kwh_day = cpu_kwh_day + ram_kwh_day + disks_kwh_day

  co2 = (total_kwh_day * KWH_CO2).round(2)
  trees_to_plant = (total_kwh_day * KWH_TREE).ceil

  trees = %w(🌲 🎄 🌳 🌴)

  trees_square = Array.new(trees_to_plant)
                   .map { trees.sample }
                   .each_slice(Math.sqrt(trees_to_plant))
                   .map { |r| r.join() }
                   .join("\n")

  puts "
For cluster #{cluster.name}
Number of vCPU in you cluster: #{vcpu}
Memory in GB you cluster: #{ram / 1024}
Number of disks in you cluster: #{disks}

Extimated [1] energy consumption of your cluster in a day: #{total_kwh_day} kWh
Extimated [2] carbon dioxide generated by the cluster running for #{days} days: #{co2} kg
Number of urban tree seedlings, grown for 10 years, that can sequester that much co2 [3]: #{trees_to_plant}

#{trees_square}
  "
end


compute_vms_from_pks_foundation

puts '
[1] Assumes taking the [TDP](https://en.wikipedia.org/wiki/Thermal_design_power) of processor and dividing
   by the number of core multiplied by 2 (each vCPU run on 1 HyperThread, 2 HyperThread on each core).
   Rounded up to 5W, to take at least in part account of the overhead of the rest of the machine other
   than the cpu.
   - Intel® Xeon® Gold 6242 Processor     - 150W - 32HT - 4.6875 W/vCPU
   - Intel® Xeon® Processor E5-2698 v3    - 135W - 32HT - 4.2188 W/vCPU
   - Intel® Xeon® Platinum 8276 Processor - 120W - 32HT - 3.75   W/vCPU
   - Intel® Xeon® Processor E5-2697 v4    - 145W - 36HT - 4.0278 W/vCPU
   Processors have been selected trying to match the GCP documentation, Google does not provide
   the exact models. https://cloud.google.com/compute/docs/cpu-platforms
[2] Calculated using https://www.epa.gov/energy/greenhouse-gas-equivalencies-calculator
[3] https://www.epa.gov/energy/greenhouse-gases-equivalencies-calculator-calculations-and-references#seedlings
'

