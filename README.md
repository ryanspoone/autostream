Stream
============

This harness performs STREAM benchmarking using GCC and OpenMPI. Capabilities include in installing prerequisites, building STREAM, and running STREAM.

Download and Run
----------------

To download these files, first install git:

```bash
yum install git
```

Or if you are using a Debian-based distribution:

```bash
apt-get install git
```

Clone this repository:

```bash
git clone http://github.com/ryanspoone/autostream.git
```

Change directories and run this script:

```bash
cd autostream/
chmod +x autostream
./autostream
```

Usage
-----

Change to directory where files are, then start benchmarking by issuing the following command:

For a full run:

```bash
./autostream
```

Customized run:

```bash
./autostream [OPTIONS...]
```

Where the options are:

| Option     | GNU long option      | Meaning                                                                                        |
|------------|----------------------|------------------------------------------------------------------------------------------------|
| -h         | --help               | Show this message.                                                                             |
| -r         | --rebuild            | Force STREAM rebuild and installation.                                                         |
| -p         | --prerequisites      | Install prerequisites.                                                                         |
| -I [value] | --iterations [value] | Set the number of iterations per OMP thread to run STREAM.                                     |
| -t [range] | --taskset [range]    | Set the core IDs to test. (e.g., 0,2,5,6-10)                                                   |
| -a         | --auto-taskset       | Automatically set the core ID range by the number of current OMP threads.                      |
| -s         | --no-scale-up        | Only do the max amount of cores.                                                               |
| -m [name]  | --march [name]       | Manually set the GCC machine architecture setting. Note: This will be -mcpu for Power systems. |
| -T [n]     | --threads [n]        | Override the number of threads to use.                                                         |

Helpful Script
--------------

The following script enables testing per socket and cross socket. It utilizes the taskset parameter to achieve this. The example is for a 96 core, 2 socket system with 16032KB of unified and data cache per thread.

1. Change to the **autostream** directory.
2. Make a file to run multiple tasksets.
     + `touch multi_taskset.sh`
3. Paste the following into the file:

     ```bash
    #!/bin/bash
    DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd)
    cd "$DIR" || exit

    # both sockets and cross sockets
    array=( "0" "48" "0-1" "48-49" "47-48" "0-3" "48-51" "46-49" "0-7" "48-55" "43-50" "0-15" "48-64" "39-54" "0-31" "48-79" "31-62" "0-47" "48-95" "23-70"
    "15-78" "7-86" "0-95" )

    cache_size=16032

    for i in "${array[@]}"; do
       printf "$cache_size\n" | ./autostream -g -s -t "$i"
    done
     ```

4. Modifiy the file with your configuration.
5. Make the file an executable.
     + `chmod +x multi_taskset.sh`
6. Run the executable.
     + `./multi_taskset.sh`

Errors
------

Error:

**/opt/thunderx/toolchain/thunderx-tools-407/aarch64-thunderx-linux-gnu/sys-root/usr/bin/../lib/gcc/aarch64-thunderx-linux-gnu/5.2.0/../../../../aarch64-thunderx-linux-gnu/bin/ld: cannot find /usr/lib64/libpthread_nonshared.a
collect2: error: ld returned 1 exit status**

Solution:

```bash
sudo ln -s /usr/lib/aarch64-linux-gnu /usr/lib64
```
