import requests
import time
from concurrent.futures import ThreadPoolExecutor

# CloudFront URL (replace with yours)
CF_URL = "https://https://d2zhvz5i43sqqg.cloudfront.net/health"

# Test locations with descriptive names and their nearest AWS regions
TEST_LOCATIONS = {
    "Mumbai (ap-south-1)": None,  # Local test from EC2
    "Singapore (ap-southeast-1)": "ap-southeast-1",
    "Tokyo (ap-northeast-1)": "ap-northeast-1",
    "Seoul (ap-northeast-2)": "ap-northeast-2",
    "Frankfurt (eu-central-1)": "eu-central-1",
    "London (eu-west-2)": "eu-west-2",
    "Virginia (us-east-1)": "us-east-1",
    "California (us-west-1)": "us-west-1"
}

def test_location(name, region):
    headers = {"Host": CF_URL.split('/')[2]}
    if region:
        # Route request through specific CloudFront edge
        headers["x-aws-edge-location"] = region
    
    try:
        start = time.time()
        r = requests.get(CF_URL, headers=headers, timeout=5)
        latency = (time.time() - start) * 1000
        return f"{name}: {latency:.2f}ms (Status: {r.status_code})"
    except Exception as e:
        return f"{name}: Failed ({str(e)})"

def main():
    print("=== Global Latency Test ===")
    print(f"Testing CloudFront URL: {CF_URL}\n")
    
    with ThreadPoolExecutor() as executor:
        results = list(executor.map(
            lambda loc: test_location(loc[0], loc[1]), 
            TEST_LOCATIONS.items()
        ))
    
    # Sort results by latency
    sorted_results = sorted(
        [r for r in results if "ms" in r],
        key=lambda x: float(x.split(":")[1].split("ms")[0]))
    
    print("\n=== Results (Fastest to Slowest) ===")
    for i, result in enumerate(sorted_results, 1):
        print(f"{i}. {result}")
    
    print(f"\nConclusion: {sorted_results[0].split(':')[0]} has the lowest latency")

if __name__ == "__main__":
    main()