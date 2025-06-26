"""
FundingPips Challenge Reward Function

This reward function evaluates trading strategies based on FundingPips
two-step challenge criteria:
- Phase 1: 8% profit target
- Phase 2: 5% profit target  
- Maximum daily drawdown: 5%
- Maximum total drawdown: 10%

The reward function penalizes strategies that exceed risk limits and
rewards profitable strategies.
"""

import numpy as np
from typing import Dict, List, Any


class FundingPipsReward:
    """
    Reward function optimized for FundingPips challenge criteria.
    
    Scoring methodology:
    - Base score: Total return percentage
    - Heavy penalties for exceeding drawdown limits
    - Bonus for achieving targets within risk limits
    """
    
    def __init__(self, phase: int = 1):
        """
        Initialize reward function.
        
        Args:
            phase: Challenge phase (1 or 2)
        """
        # Phase 1: 8%, Phase 2: 5%
        self.target_return = 8.0 if phase == 1 else 5.0
        self.max_daily_dd = 5.0    # Maximum daily drawdown %
        self.max_total_dd = 10.0   # Maximum total drawdown %
        self.phase = phase
        
    def calculate_reward(self, backtest_results: Dict[str, Any]) -> float:
        """
        Compute net reward: %return minus penalties for excess drawdown.
        
        Args:
            backtest_results: Dictionary containing:
                - equity_curve: List of equity values over time
                - daily_returns: List of daily return percentages
                - trades: List of trade records
                
        Returns:
            reward: Net reward score (higher = better)
        """
        try:
            # Extract key metrics
            equity_curve = backtest_results.get("equity_curve", [])
            daily_returns = backtest_results.get("daily_returns", [])
            
            if not equity_curve or len(equity_curve) < 2:
                return -1000  # Invalid backtest
                
            # Calculate total return
            total_return = (equity_curve[-1] / equity_curve[0] - 1.0) * 100
            
            # Calculate drawdown metrics
            daily_dd = self._calculate_daily_drawdown(daily_returns)
            total_dd = self._calculate_total_drawdown(equity_curve)
            
            # Base score is total return
            base_score = total_return
            
            # Apply penalties for risk violations
            penalty = 0
            
            # Daily drawdown penalty (exponential penalty for violations)
            if daily_dd > self.max_daily_dd:
                excess_daily = daily_dd - self.max_daily_dd
                penalty += excess_daily * 20  # Heavy penalty
                
            # Total drawdown penalty
            if total_dd > self.max_total_dd:
                excess_total = total_dd - self.max_total_dd
                penalty += excess_total * 50  # Very heavy penalty
                
            # Bonus for achieving target within risk limits
            bonus = 0
            if (total_return >= self.target_return and
                    daily_dd <= self.max_daily_dd and
                    total_dd <= self.max_total_dd):
                bonus = 20  # Significant bonus for meeting all criteria
                
            # Additional penalties for poor trading behavior
            penalty += self._calculate_trading_penalties(backtest_results)
            
            # Final reward calculation
            reward = base_score + bonus - penalty
            
            return reward
            
        except Exception as e:
            print(f"Error calculating reward: {e}")
            return -1000
            
    def _calculate_daily_drawdown(self, daily_returns: List[float]) -> float:
        """Calculate maximum daily drawdown percentage."""
        if not daily_returns:
            return 0.0
            
        # Convert to numpy array for easier computation
        returns = np.array(daily_returns, dtype=float)
        
        # Calculate running maximum
        cumulative_returns = np.cumsum(returns)
        running_max = np.maximum.accumulate(cumulative_returns)
        
        # Calculate drawdown from peak
        drawdown = (running_max - cumulative_returns) / running_max * 100
        
        return float(np.max(drawdown))
        
    def _calculate_total_drawdown(self,
                                  equity_curve: List[float]) -> float:
        """Calculate maximum total drawdown percentage."""
        if len(equity_curve) < 2:
            return 0.0
            
        # Convert to numpy array
        equity = np.array(equity_curve, dtype=float)
        
        # Calculate running maximum
        running_max = np.maximum.accumulate(equity)
        
        # Calculate drawdown percentage
        drawdown = (running_max - equity) / running_max * 100
        
        return float(np.max(drawdown))
        
    def _calculate_trading_penalties(
            self,
            backtest_results: Dict[str, Any]) -> float:
        """Calculate additional penalties for poor trading behavior."""
        penalty = 0
        
        # Get trade data if available
        trades = backtest_results.get("trades", [])
        
        if trades:
            # Penalty for over-trading (too many trades)
            if len(trades) > 1000:  # Arbitrary threshold
                penalty += (len(trades) - 1000) * 0.1
                
            # Penalty for very low win rate
            winning_trades = [t for t in trades if t.get("pnl", 0) > 0]
            if len(trades) > 0:
                win_rate = len(winning_trades) / len(trades)
                if win_rate < 0.3:  # Less than 30% win rate
                    penalty += (0.3 - win_rate) * 100
                    
        return penalty
        
    def get_metrics_summary(self,
                            backtest_results: Dict[str, Any]) -> Dict[str, float]:
        """Get detailed metrics summary for analysis."""
        equity_curve = backtest_results.get("equity_curve", [])
        daily_returns = backtest_results.get("daily_returns", [])
        
        if not equity_curve:
            return {}
            
        total_return = (equity_curve[-1] / equity_curve[0] - 1.0) * 100
        daily_dd = self._calculate_daily_drawdown(daily_returns)
        total_dd = self._calculate_total_drawdown(equity_curve)
        reward = self.calculate_reward(backtest_results)
        
        return {
            "total_return": total_return,
            "daily_drawdown": daily_dd,
            "total_drawdown": total_dd,
            "reward_score": reward,
            "target_return": self.target_return,
            "meets_daily_dd_limit": daily_dd <= self.max_daily_dd,
            "meets_total_dd_limit": total_dd <= self.max_total_dd,
            "meets_target": total_return >= self.target_return,
            "challenge_passed": (total_return >= self.target_return and
                                 daily_dd <= self.max_daily_dd and
                                 total_dd <= self.max_total_dd)
        }


# Example usage and testing
if __name__ == "__main__":
    # Test with sample data
    reward_func = FundingPipsReward(phase=1)
    
    # Mock backtest results
    sample_results = {
        "equity_curve": [1000, 1020, 1050, 1030, 1080, 1100],
        "daily_returns": [2.0, 3.0, -2.0, 5.0, 2.0],
        "trades": [{"pnl": 20}, {"pnl": 30}, {"pnl": -20}, {"pnl": 50}]
    }
    
    reward = reward_func.calculate_reward(sample_results)
    metrics = reward_func.get_metrics_summary(sample_results)
    
    print(f"Reward Score: {reward:.2f}")
    print(f"Metrics: {metrics}") 