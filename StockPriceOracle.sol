pragma solidity ^0.8.20;
import { FunctionsRequest } from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";
import { FunctionsClient } from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "hardhat/console.sol";
import { LinkTokenInterface } from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";


interface TokenizedUSStockInterface {
    function updateStockData(
        string memory symbol,
        uint256 price,
        uint256 dividendAmount,
        uint256 nextDividendDate
    ) external;
    function getAvailableStocks() external view returns (string[] memory);
    function getLinkToken() external view returns (LinkTokenInterface);
}
contract StockPriceOracle is FunctionsClient, ConfirmedOwner, AutomationCompatibleInterface {

    TokenizedUSStockInterface public tokenizedStock;
    bytes32 public latestRequestId;
    bytes public latestResponse;

    error UnexpectedRequest(bytes32 requestId);

    event Response(bytes32 indexed requestId, bytes response);
    event ErrorResponse(string reason);

    string public source;

    constructor(
        address oracle,
        address router,
        address _tokenizedStockAddress,
        uint64 _subscriptionId,
        bytes memory _source
    ) ConfirmedOwner(msg.sender) FunctionsClient(oracle, router) {
        tokenizedStock = TokenizedUSStockInterface(_tokenizedStockAddress);
        setChainlinkToken(address(tokenizedStock.getLinkToken()));
        s_oracle = oracle;
         s_updateSubscription(_subscriptionId); // Initiate Functions subscription
        donHostedSource = _source;
    }

    function updateStockData(string memory _symbol) public onlyOwner {
        FunctionsRequest.Request memory req;
        req.initializeRequest(Functions.Location.Inline,Functions.CodeLanguage.JavaScript, donHostedSource);
        req.encodeParams(
            _symbol
        );
        sendRequest(req);
    }

    function checkUpkeep(bytes calldata /* checkData */) external view override returns (bool upkeepNeeded, bytes memory performData) {
        upkeepNeeded = true;
        performData = abi.encode(""); // Encode the array of stock symbols (if needed)
    }

    function performUpkeep(bytes calldata performData) external override {
        string[] memory symbolsToUpdate = abi.decode(performData, (string[]));
        if (symbolsToUpdate.length == 0) {
            symbolsToUpdate = tokenizedStock.getAvailableStocks();
        }

        for (uint256 i = 0; i < symbolsToUpdate.length; i++) {
            updateStockData(symbolsToUpdate[i]);
        }
    }
    

    // Callback for Chainlink Functions response
    function fulfillRequest(
        bytes32 _requestId,
        bytes memory _response
    ) internal override {
        if (latestRequestId != _requestId) {
            revert UnexpectedRequest(_requestId);
        }
        latestResponse = _response;
        emit Response(_requestId, _response);

        (string memory symbol, uint256 price, uint256 dividendAmount, uint256 nextDividendDate) = 
            _parseApiResponse(_response);
        tokenizedStock.updateStockData(symbol, price, dividendAmount, nextDividendDate);
    }

    // Function to parse the JSON response from Alpha Vantage
    function _parseApiResponse(bytes memory _response)
        internal
        pure
        returns (string memory symbol, uint256 price, uint256 dividendAmount, uint256 nextDividendDate)
    {
        // Sample Parsing Logic (adjust for your specific API response structure)
        // You may need a JSON parsing library for more complex responses
        (symbol, price, dividendAmount, nextDividendDate) = abi.decode(_response, (string, uint256, uint256, uint256));
    }

    // Helper function to extract a string value from the JSON response
    function _getStringFromResponse(bytes memory _response, string memory _key) internal pure returns (string memory value) {
        bytes32 keyHash = keccak256(abi.encodePacked("\"", _key, "\":\""));
        uint256 start = _findKeyStart(_response, keyHash);
        if (start == 0) {
            return "";
        }
        uint256 end = _findKeyEnd(_response, start);
        return string(abi.encodePacked(_response[start:end]));
    }

    // Helper function to extract a uint256 value from the JSON response
    function _getUintFromResponse(bytes memory _response, string memory _key) internal pure returns (uint256 value) {
        string memory strValue = _getStringFromResponse(_response, _key);
        value = _stringToUint(strValue);
    }

    function _findKeyStart(bytes memory _response, bytes32 _keyHash) internal pure returns (uint256) {
        for (uint256 i = 0; i < _response.length - 32; i++) {
            if (keccak256(abi.encodePacked(_response[i:i+32])) == _keyHash) {
                return i + 32;
            }
        }
        return 0;
    }

    function _findKeyEnd(bytes memory _response, uint256 _start) internal pure returns (uint256) {
        for (uint256 i = _start; i < _response.length; i++) {
            if (_response[i] == '"') {
                return i;
            }
        }
        return 0;
    }

    function _stringToUint(string memory s) internal pure returns (uint256 result) {
        bytes memory b = bytes(s);
        uint256 i;
        result = 0;
        for (i = 0; i < b.length; i++) {
            uint8 c = uint8(b[i]);
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            } else if (c == 46) { // Handle decimal point
                uint256 decimalPart = 0;
                for (uint j = i + 1; j < b.length; j++) {
                    c = uint8(b[j]);
                    if (c >= 48 && c <= 57) {
                        decimalPart = decimalPart * 10 + (c - 48);
                    }
                }
                result = result * 100 + decimalPart; // Adjust for 2 decimal places (0.01)
                break;
            }
        }
    }

    function _stringToTimestamp(string memory _dateString) internal pure returns (uint256) {
        // ... your string to timestamp conversion logic here
    }
}
